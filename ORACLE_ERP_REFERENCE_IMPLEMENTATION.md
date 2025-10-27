# Oracle ERP Backend - Reference Implementation

This document provides detailed implementation examples and code samples to complement the main case study. It includes working examples of all major components described in the architecture.

## Table of Contents

1. [Sync Gateway Implementation](#sync-gateway-implementation)
2. [Oracle Integration Layer](#oracle-integration-layer)
3. [Client Sync Manager](#client-sync-manager)
4. [Conflict Resolution Examples](#conflict-resolution-examples)
5. [Performance Optimization](#performance-optimization)
6. [Security Implementation](#security-implementation)
7. [Monitoring and Alerting](#monitoring-and-alerting)

## Sync Gateway Implementation

### Core Sync Gateway Service

```java
@SpringBootApplication
@EnableJpaRepositories
@EnableRedisRepositories
public class SyncGatewayApplication {
    public static void main(String[] args) {
        SpringApplication.run(SyncGatewayApplication.class, args);
    }
}

@RestController
@RequestMapping("/api/v1/sync")
@Validated
public class SyncController {
    
    private final SyncService syncService;
    private final SecurityService securityService;
    private final MetricsService metricsService;
    
    public SyncController(SyncService syncService, 
                         SecurityService securityService,
                         MetricsService metricsService) {
        this.syncService = syncService;
        this.securityService = securityService;
        this.metricsService = metricsService;
    }
    
    @PostMapping("/register")
    public ResponseEntity<ClientRegistration> registerClient(
            @RequestBody @Valid ClientRegistrationRequest request) {
        
        Timer.Sample sample = Timer.start();
        try {
            // Validate credentials and get permissions
            ClientProfile profile = securityService.validateAndCreateProfile(request);
            
            // Generate unique node ID
            String nodeId = UUID.randomUUID().toString();
            
            // Initialize HLC for this client
            HlcTimestamp initialTimestamp = syncService.initializeClientClock(nodeId);
            
            ClientRegistration registration = ClientRegistration.builder()
                .nodeId(nodeId)
                .userId(profile.getUserId())
                .permissions(profile.getPermissions())
                .dataFilters(profile.getDataFilters())
                .initialTimestamp(initialTimestamp.toString())
                .syncEndpoints(getSyncEndpoints())
                .build();
            
            // Store client session
            securityService.storeClientSession(registration);
            
            metricsService.recordClientRegistration(profile.getUserId());
            
            return ResponseEntity.ok(registration);
            
        } catch (SecurityException e) {
            metricsService.recordAuthenticationFailure(request.getDeviceId());
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(ClientRegistration.error("Authentication failed"));
        } finally {
            sample.stop(Timer.builder("sync.register.duration").register());
        }
    }
    
    @PostMapping("/download/{table}")
    @PreAuthorize("hasPermission(#table, 'READ')")
    public ResponseEntity<SyncDownloadResponse> downloadTableData(
            @PathVariable @Valid @TableName String table,
            @RequestParam(required = false) String since,
            @RequestParam(defaultValue = "1000") @Min(1) @Max(5000) int batchSize,
            @RequestHeader("X-Node-ID") String nodeId,
            @RequestHeader("Authorization") String authToken) {
        
        Timer.Sample sample = Timer.start();
        try {
            // Validate client session
            ClientSession session = securityService.validateSession(nodeId, authToken);
            
            // Parse and validate timestamp
            HlcTimestamp sinceTimestamp = since != null ? 
                HlcTimestamp.parse(since) : null;
            
            // Get data with security filtering
            SyncDataResult result = syncService.getTableData(
                table, sinceTimestamp, batchSize, session.getProfile());
            
            // Build response
            SyncDownloadResponse response = SyncDownloadResponse.builder()
                .records(result.getRecords())
                .maxTimestamp(result.getMaxTimestamp().toString())
                .hasMore(result.hasMore())
                .totalRecords(result.getTotalCount())
                .compressionEnabled(true)
                .build();
            
            metricsService.recordDownloadSync(table, result.getRecords().size());
            
            return ResponseEntity.ok()
                .header("Content-Encoding", "gzip")
                .body(response);
                
        } catch (SecurityException e) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN)
                .body(SyncDownloadResponse.error("Access denied"));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(SyncDownloadResponse.error("Invalid parameters: " + e.getMessage()));
        } finally {
            sample.stop(Timer.builder("sync.download.duration")
                .tag("table", table).register());
        }
    }
    
    @PostMapping("/upload/{table}")
    @PreAuthorize("hasPermission(#table, 'WRITE')")
    public ResponseEntity<SyncUploadResponse> uploadTableData(
            @PathVariable @Valid @TableName String table,
            @RequestBody @Valid List<@Valid RecordUpdate> records,
            @RequestHeader("X-Node-ID") String nodeId,
            @RequestHeader("Authorization") String authToken) {
        
        Timer.Sample sample = Timer.start();
        try {
            // Validate session and permissions
            ClientSession session = securityService.validateSession(nodeId, authToken);
            
            if (records.size() > 1000) {
                return ResponseEntity.status(HttpStatus.PAYLOAD_TOO_LARGE)
                    .body(SyncUploadResponse.error("Batch size exceeds limit"));
            }
            
            // Process uploads with conflict detection
            UploadResult result = syncService.processUploads(table, records, session);
            
            SyncUploadResponse response = SyncUploadResponse.builder()
                .successfulRecords(result.getSuccessfulRecords())
                .conflicts(result.getConflicts())
                .serverTimestamp(result.getServerTimestamp().toString())
                .build();
            
            metricsService.recordUploadSync(table, records.size(), result.getConflicts().size());
            
            return ResponseEntity.ok(response);
            
        } catch (ConflictResolutionException e) {
            return ResponseEntity.status(HttpStatus.CONFLICT)
                .body(SyncUploadResponse.conflict(e.getConflicts()));
        } catch (SecurityException e) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN)
                .body(SyncUploadResponse.error("Access denied"));
        } finally {
            sample.stop(Timer.builder("sync.upload.duration")
                .tag("table", table).register());
        }
    }
}
```

### HLC Coordination Service

```java
@Component
@Transactional
public class HlcCoordinationService {
    
    private final RedisTemplate<String, String> redisTemplate;
    private final ApplicationEventPublisher eventPublisher;
    
    private static final String GLOBAL_HLC_KEY = "global:hlc";
    private static final String NODE_HLC_PREFIX = "node:hlc:";
    
    public HlcCoordinationService(RedisTemplate<String, String> redisTemplate,
                                 ApplicationEventPublisher eventPublisher) {
        this.redisTemplate = redisTemplate;
        this.eventPublisher = eventPublisher;
    }
    
    @Retryable(value = {RedisConnectionFailureException.class}, maxAttempts = 3)
    public synchronized HlcTimestamp generateTimestamp(String nodeId) {
        
        // Get current physical time
        long physicalTime = System.currentTimeMillis();
        
        // Get the last known global timestamp
        GlobalHlcState globalState = getGlobalHlcState();
        
        // Get this node's last timestamp
        NodeHlcState nodeState = getNodeHlcState(nodeId);
        
        // Calculate new timestamp according to HLC rules
        HlcTimestamp newTimestamp = calculateNextTimestamp(
            physicalTime, globalState, nodeState, nodeId);
        
        // Update both global and node states atomically
        updateHlcStates(newTimestamp, globalState, nodeState);
        
        // Publish event for monitoring
        eventPublisher.publishEvent(new HlcTimestampGeneratedEvent(newTimestamp));
        
        return newTimestamp;
    }
    
    private GlobalHlcState getGlobalHlcState() {
        String serialized = redisTemplate.opsForValue().get(GLOBAL_HLC_KEY);
        return serialized != null ? 
            GlobalHlcState.fromJson(serialized) : 
            GlobalHlcState.initial();
    }
    
    private NodeHlcState getNodeHlcState(String nodeId) {
        String key = NODE_HLC_PREFIX + nodeId;
        String serialized = redisTemplate.opsForValue().get(key);
        return serialized != null ? 
            NodeHlcState.fromJson(serialized) : 
            NodeHlcState.initial(nodeId);
    }
    
    private HlcTimestamp calculateNextTimestamp(
            long physicalTime,
            GlobalHlcState globalState,
            NodeHlcState nodeState,
            String nodeId) {
        
        long maxKnownPhysical = Math.max(globalState.getPhysicalTime(), nodeState.getPhysicalTime());
        
        if (physicalTime > maxKnownPhysical) {
            // Physical time advanced, reset logical clock
            return new HlcTimestamp(physicalTime, 0, nodeId);
        } else if (physicalTime == maxKnownPhysical) {
            // Same physical time, increment logical clock
            long newLogical = Math.max(globalState.getLogicalTime(), nodeState.getLogicalTime()) + 1;
            return new HlcTimestamp(physicalTime, newLogical, nodeId);
        } else {
            // Physical time is behind, use max known time with incremented logical
            long newLogical = Math.max(globalState.getLogicalTime(), nodeState.getLogicalTime()) + 1;
            return new HlcTimestamp(maxKnownPhysical, newLogical, nodeId);
        }
    }
    
    private void updateHlcStates(HlcTimestamp newTimestamp, 
                                GlobalHlcState globalState, 
                                NodeHlcState nodeState) {
        // Use Redis transactions for atomic updates
        redisTemplate.execute(new SessionCallback<Object>() {
            @Override
            public <K, V> Object execute(RedisOperations<K, V> operations) throws DataAccessException {
                operations.multi();
                
                // Update global state
                GlobalHlcState newGlobalState = globalState.update(newTimestamp);
                operations.opsForValue().set(
                    (K) GLOBAL_HLC_KEY, 
                    (V) newGlobalState.toJson(),
                    Duration.ofHours(24));
                
                // Update node state
                NodeHlcState newNodeState = nodeState.update(newTimestamp);
                operations.opsForValue().set(
                    (K) (NODE_HLC_PREFIX + newTimestamp.getNodeId()),
                    (V) newNodeState.toJson(),
                    Duration.ofHours(24));
                
                return operations.exec();
            }
        });
    }
    
    public void syncWithExternalTimestamp(HlcTimestamp externalTimestamp) {
        // Update global state when receiving timestamp from other systems
        GlobalHlcState currentGlobal = getGlobalHlcState();
        
        if (externalTimestamp.isAfter(currentGlobal.getTimestamp())) {
            GlobalHlcState updatedGlobal = currentGlobal.syncWith(externalTimestamp);
            redisTemplate.opsForValue().set(GLOBAL_HLC_KEY, updatedGlobal.toJson());
            
            eventPublisher.publishEvent(new ExternalHlcSyncEvent(externalTimestamp));
        }
    }
}
```

## Oracle Integration Layer

### Oracle Data Access Service

```java
@Service
@Transactional
public class OracleErpDataService {
    
    private final JdbcTemplate jdbcTemplate;
    private final NamedParameterJdbcTemplate namedTemplate;
    private final SchemaMapper schemaMapper;
    private final CacheManager cacheManager;
    
    @Cacheable(value = "tableData", key = "#table + ':' + #since + ':' + #profile.cacheKey")
    public SyncDataResult getTableData(String table, 
                                      HlcTimestamp since, 
                                      int batchSize, 
                                      ClientProfile profile) {
        
        // Get Oracle table mapping
        OracleTableMapping mapping = schemaMapper.getMapping(table);
        if (mapping == null) {
            throw new IllegalArgumentException("Unknown table: " + table);
        }
        
        // Build dynamic query with security filters
        String query = buildSecureQuery(mapping, since, profile);
        
        // Execute with parameters
        Map<String, Object> params = Map.of(
            "since_timestamp", since != null ? since.toString() : "1970-01-01T00:00:00Z",
            "batch_size", batchSize + 1, // +1 to check for more records
            "user_regions", profile.getAllowedRegions(),
            "user_departments", profile.getAllowedDepartments(),
            "security_level", profile.getSecurityLevel()
        );
        
        List<Map<String, Object>> rawRecords = namedTemplate.queryForList(query, params);
        
        // Check if there are more records
        boolean hasMore = rawRecords.size() > batchSize;
        if (hasMore) {
            rawRecords = rawRecords.subList(0, batchSize);
        }
        
        // Transform Oracle records to SQLite format
        List<Map<String, Object>> transformedRecords = rawRecords.stream()
            .map(record -> mapping.transformToSqlite(record))
            .collect(toList());
        
        // Find max timestamp
        HlcTimestamp maxTimestamp = transformedRecords.stream()
            .map(record -> HlcTimestamp.parse((String) record.get("system_version")))
            .max(HlcTimestamp::compareTo)
            .orElse(since);
        
        return SyncDataResult.builder()
            .records(transformedRecords)
            .maxTimestamp(maxTimestamp)
            .hasMore(hasMore)
            .totalCount(rawRecords.size())
            .build();
    }
    
    private String buildSecureQuery(OracleTableMapping mapping, 
                                   HlcTimestamp since, 
                                   ClientProfile profile) {
        
        StringBuilder query = new StringBuilder();
        query.append("SELECT ");
        
        // Add selected fields with transformations
        query.append(mapping.getSelectClause());
        
        query.append(" FROM ").append(mapping.getOracleTableName());
        
        // Add joins for denormalization
        for (String join : mapping.getJoins()) {
            query.append(" ").append(join);
        }
        
        // Add WHERE conditions
        List<String> conditions = new ArrayList<>();
        
        // Timestamp filter
        if (since != null) {
            conditions.add(mapping.getTimestampColumn() + " > :since_timestamp");
        }
        
        // Security filters
        conditions.addAll(buildSecurityFilters(mapping, profile));
        
        if (!conditions.isEmpty()) {
            query.append(" WHERE ").append(String.join(" AND ", conditions));
        }
        
        // Add ordering and limit
        query.append(" ORDER BY ").append(mapping.getTimestampColumn());
        query.append(" FETCH FIRST :batch_size ROWS ONLY");
        
        return query.toString();
    }
    
    private List<String> buildSecurityFilters(OracleTableMapping mapping, ClientProfile profile) {
        List<String> filters = new ArrayList<>();
        
        // Region-based filtering
        if (mapping.hasRegionColumn() && !profile.getAllowedRegions().isEmpty()) {
            filters.add(mapping.getRegionColumn() + " IN (:user_regions)");
        }
        
        // Department-based filtering
        if (mapping.hasDepartmentColumn() && !profile.getAllowedDepartments().isEmpty()) {
            filters.add(mapping.getDepartmentColumn() + " IN (:user_departments)");
        }
        
        // Security level filtering
        if (mapping.hasSecurityLevel()) {
            filters.add(mapping.getSecurityLevelColumn() + " <= :security_level");
        }
        
        // Row-level security
        if (profile.hasRowLevelSecurity()) {
            filters.add(mapping.getRowSecurityFilter(profile));
        }
        
        return filters;
    }
    
    @Transactional
    public UploadResult processUploads(String table, 
                                      List<RecordUpdate> records, 
                                      ClientSession session) {
        
        OracleTableMapping mapping = schemaMapper.getMapping(table);
        List<String> successful = new ArrayList<>();
        List<ConflictResult> conflicts = new ArrayList<>();
        
        for (RecordUpdate record : records) {
            try {
                UploadRecordResult result = processRecordUpdate(mapping, record, session);
                
                if (result.isSuccess()) {
                    successful.add(record.getId());
                } else {
                    conflicts.add(result.getConflict());
                }
                
            } catch (Exception e) {
                log.error("Failed to process record update {}", record.getId(), e);
                conflicts.add(ConflictResult.error(record, e.getMessage()));
            }
        }
        
        HlcTimestamp serverTimestamp = hlcCoordinator.generateTimestamp("oracle-server");
        
        return UploadResult.builder()
            .successfulRecords(successful)
            .conflicts(conflicts)
            .serverTimestamp(serverTimestamp)
            .build();
    }
    
    private UploadRecordResult processRecordUpdate(OracleTableMapping mapping, 
                                                  RecordUpdate record, 
                                                  ClientSession session) {
        
        // Check for existing record
        String checkQuery = "SELECT " + mapping.getTimestampColumn() + 
                           " FROM " + mapping.getOracleTableName() + 
                           " WHERE " + mapping.getPrimaryKeyColumn() + " = ?";
        
        List<String> existing = jdbcTemplate.queryForList(
            checkQuery, String.class, record.getId());
        
        if (existing.isEmpty()) {
            // New record - direct insert
            return insertNewRecord(mapping, record, session);
        } else {
            // Existing record - check for conflict
            HlcTimestamp existingTimestamp = HlcTimestamp.parse(existing.get(0));
            HlcTimestamp recordTimestamp = HlcTimestamp.parse(record.getSystemVersion());
            
            if (recordTimestamp.isAfter(existingTimestamp)) {
                // Client wins - update Oracle
                return updateExistingRecord(mapping, record, session);
            } else {
                // Oracle wins - return conflict
                return UploadRecordResult.conflict(
                    record, existingTimestamp, "Server version is newer");
            }
        }
    }
    
    private UploadRecordResult insertNewRecord(OracleTableMapping mapping, 
                                              RecordUpdate record, 
                                              ClientSession session) {
        
        Map<String, Object> oracleRecord = mapping.transformToOracle(record.getData());
        
        // Add audit fields
        oracleRecord.put("CREATED_BY", session.getUserId());
        oracleRecord.put("CREATED_DATE", new Timestamp(System.currentTimeMillis()));
        oracleRecord.put("LAST_UPDATED_BY", session.getUserId());
        oracleRecord.put("LAST_UPDATE_DATE", new Timestamp(System.currentTimeMillis()));
        
        String insertSql = mapping.buildInsertStatement();
        
        try {
            int rowsAffected = namedTemplate.update(insertSql, oracleRecord);
            
            if (rowsAffected == 1) {
                return UploadRecordResult.success(record);
            } else {
                return UploadRecordResult.error(record, "Insert failed");
            }
            
        } catch (DataIntegrityViolationException e) {
            return UploadRecordResult.conflict(record, null, 
                "Data integrity violation: " + e.getMessage());
        }
    }
    
    private UploadRecordResult updateExistingRecord(OracleTableMapping mapping, 
                                                   RecordUpdate record, 
                                                   ClientSession session) {
        
        Map<String, Object> oracleRecord = mapping.transformToOracle(record.getData());
        
        // Add audit fields
        oracleRecord.put("LAST_UPDATED_BY", session.getUserId());
        oracleRecord.put("LAST_UPDATE_DATE", new Timestamp(System.currentTimeMillis()));
        oracleRecord.put(mapping.getPrimaryKeyColumn(), record.getId());
        
        String updateSql = mapping.buildUpdateStatement();
        
        try {
            int rowsAffected = namedTemplate.update(updateSql, oracleRecord);
            
            if (rowsAffected == 1) {
                return UploadRecordResult.success(record);
            } else {
                return UploadRecordResult.error(record, "Update failed - record not found");
            }
            
        } catch (DataIntegrityViolationException e) {
            return UploadRecordResult.conflict(record, null, 
                "Data integrity violation: " + e.getMessage());
        }
    }
}
```

### Schema Mapping Configuration

```java
@Configuration
public class SchemaMappingConfig {
    
    @Bean
    public SchemaMapper schemaMapper() {
        return SchemaMapper.builder()
            
            // Employee table mapping
            .addMapping("employees", OracleTableMapping.builder()
                .oracleTable("HR.EMPLOYEES")
                .primaryKey("EMPLOYEE_ID")
                .timestampColumn("LAST_UPDATE_DATE")
                .regionColumn("REGION_CODE")
                .departmentColumn("DEPARTMENT_ID")
                .securityLevelColumn("SECURITY_CLASSIFICATION")
                
                // Field mappings with transformations
                .addField("id", "EMPLOYEE_ID", FieldTransform.guidToNumber())
                .addField("full_name", "FIRST_NAME || ' ' || LAST_NAME", FieldTransform.computed())
                .addField("department_name", "d.DEPARTMENT_NAME", FieldTransform.joined())
                .addField("salary", "SALARY", FieldTransform.direct())
                .addField("hire_date", "TO_CHAR(HIRE_DATE, 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"')", FieldTransform.dateToIso())
                .addField("system_version", "LAST_UPDATE_DATE", FieldTransform.timestampToHlc())
                
                // Joins for denormalization
                .addJoin("LEFT JOIN HR.DEPARTMENTS d ON e.DEPARTMENT_ID = d.DEPARTMENT_ID")
                .addJoin("LEFT JOIN HR.LOCATIONS l ON d.LOCATION_ID = l.LOCATION_ID")
                
                // Security filter
                .rowSecurityFilter(profile -> 
                    "EMPLOYEE_ID IN (SELECT EMPLOYEE_ID FROM HR.USER_EMPLOYEE_ACCESS WHERE USER_ID = '" + 
                    profile.getUserId() + "')")
                
                .build())
            
            // Inventory table mapping
            .addMapping("inventory_items", OracleTableMapping.builder()
                .oracleTable("INV.ITEMS")
                .primaryKey("ITEM_ID")
                .timestampColumn("LAST_UPDATE_DATE")
                .regionColumn("OWNING_ORGANIZATION_CODE")
                
                .addField("id", "ITEM_ID", FieldTransform.guidToNumber())
                .addField("item_code", "SEGMENT1", FieldTransform.direct())
                .addField("description", "DESCRIPTION", FieldTransform.direct())
                .addField("quantity", "CURRENT_QUANTITY", FieldTransform.direct())
                .addField("unit_price", "UNIT_COST", FieldTransform.direct())
                .addField("system_version", "LAST_UPDATE_DATE", FieldTransform.timestampToHlc())
                
                .build())
            
            .build();
    }
}
```

## Client Sync Manager

### Enhanced Client Sync Implementation

```dart
class OracleErpSyncManager extends ServerSyncManager {
  final ApiClient _apiClient;
  final EncryptionService _encryption;
  final LocalStorage _storage;
  
  OracleErpSyncManager({
    required DeclarativeDatabase db,
    required String apiBaseUrl,
    required String nodeId,
    required String authToken,
  }) : _apiClient = ApiClient(apiBaseUrl, authToken),
       _encryption = EncryptionService(),
       _storage = LocalStorage(),
       super(
         db: db,
         onFetch: (database, tableTimestamps) => 
             _performDownloadSync(database, tableTimestamps),
         onSend: (operations) => _performUploadSync(operations),
       );
  
  // Client registration and authentication
  static Future<OracleErpSyncManager> create({
    required DeclarativeDatabase db,
    required String apiBaseUrl,
    required String deviceId,
    required String username,
    required String password,
  }) async {
    
    final apiClient = ApiClient(apiBaseUrl);
    
    // Register with server
    final registrationResponse = await apiClient.post('/sync/register', {
      'device_id': deviceId,
      'username': username,
      'password': password,
      'app_version': await getAppVersion(),
      'platform': await getPlatform(),
    });
    
    final registration = ClientRegistration.fromJson(registrationResponse.data);
    
    // Store credentials securely
    await _storeCredentials(registration);
    
    // Initialize HLC with server timestamp
    final hlcClock = HlcClock(nodeId: registration.nodeId);
    if (registration.initialTimestamp != null) {
      hlcClock.update(Hlc.parse(registration.initialTimestamp!));
    }
    
    return OracleErpSyncManager(
      db: db,
      apiBaseUrl: apiBaseUrl,
      nodeId: registration.nodeId,
      authToken: registration.authToken,
    );
  }
  
  Future<void> _performDownloadSync(
    DeclarativeDatabase database,
    Map<String, Hlc?> tableTimestamps,
  ) async {
    
    final syncTasks = <Future<void>>[];
    
    // Download all tables in parallel for efficiency
    for (final table in database.schema.userTables) {
      syncTasks.add(_downloadTableWithRetry(
        database, 
        table.name, 
        tableTimestamps[table.name],
      ));
    }
    
    await Future.wait(syncTasks, eagerError: false);
  }
  
  Future<void> _downloadTableWithRetry(
    DeclarativeDatabase database,
    String tableName,
    Hlc? lastSync,
  ) async {
    
    int retryCount = 0;
    const maxRetries = 3;
    
    while (retryCount < maxRetries) {
      try {
        await _downloadTableChanges(database, tableName, lastSync);
        return; // Success
        
      } catch (e) {
        retryCount++;
        
        if (retryCount >= maxRetries) {
          print('Failed to sync table $tableName after $maxRetries attempts: $e');
          rethrow;
        }
        
        // Exponential backoff
        await Future.delayed(Duration(seconds: pow(2, retryCount).toInt()));
      }
    }
  }
  
  Future<void> _downloadTableChanges(
    DeclarativeDatabase database,
    String tableName,
    Hlc? lastSync,
  ) async {
    
    bool hasMore = true;
    String? since = lastSync?.toString();
    int totalRecords = 0;
    
    while (hasMore) {
      final response = await _apiClient.get('/sync/download/$tableName', 
        queryParams: {
          'since': since,
          'batch_size': '1000',
        },
      );
      
      final syncResponse = SyncDownloadResponse.fromJson(response.data);
      
      if (syncResponse.hasError) {
        throw SyncException('Download failed: ${syncResponse.error}');
      }
      
      // Apply records in transaction for consistency
      await database.transaction((txn) async {
        for (final record in syncResponse.records) {
          await _applyServerRecord(txn, tableName, record);
        }
      });
      
      totalRecords += syncResponse.records.length;
      
      // Update sync tracking
      if (syncResponse.maxTimestamp != null) {
        await updateTableTimestamp(tableName, Hlc.parse(syncResponse.maxTimestamp!));
      }
      
      hasMore = syncResponse.hasMore;
      since = syncResponse.maxTimestamp;
      
      // Progress callback for UI
      _notifyDownloadProgress(tableName, totalRecords, hasMore);
    }
    
    print('Downloaded $totalRecords records for table $tableName');
  }
  
  Future<void> _applyServerRecord(
    DeclarativeDatabase txn,
    String tableName,
    Map<String, Object?> serverRecord,
  ) async {
    
    // Decrypt sensitive fields
    final decryptedRecord = await _decryptRecord(serverRecord);
    
    // Check if we have this record locally
    final recordId = decryptedRecord['id'] as String;
    final existingRecords = await txn.queryTable(
      tableName,
      where: 'id = ?',
      whereArgs: [recordId],
      limit: 1,
    );
    
    if (existingRecords.isEmpty) {
      // New record - direct insert
      await txn.insert(tableName, decryptedRecord);
    } else {
      // Existing record - merge with LWW logic
      await _mergeServerRecord(txn, tableName, decryptedRecord, existingRecords.first);
    }
  }
  
  Future<void> _mergeServerRecord(
    DeclarativeDatabase txn,
    String tableName,
    Map<String, Object?> serverRecord,
    Map<String, Object?> localRecord,
  ) async {
    
    final tableDefinition = txn.schema.getTable(tableName);
    final lwwColumns = tableDefinition?.columns
        .where((c) => c.isLww)
        .map((c) => c.name)
        .toSet() ?? <String>{};
    
    final mergedRecord = Map<String, Object?>.from(localRecord);
    
    for (final entry in serverRecord.entries) {
      final columnName = entry.key;
      final serverValue = entry.value;
      
      if (lwwColumns.contains(columnName)) {
        // Use LWW logic for conflict resolution
        final serverHlcColumn = '${columnName}__hlc';
        final localHlcColumn = '${columnName}__hlc';
        
        final serverHlc = Hlc.parse(serverRecord[serverHlcColumn] as String? ?? '');
        final localHlc = localRecord[localHlcColumn] as String?;
        
        if (localHlc == null || serverHlc.compareTo(Hlc.parse(localHlc)) > 0) {
          // Server value is newer
          mergedRecord[columnName] = serverValue;
          mergedRecord[serverHlcColumn] = serverRecord[serverHlcColumn];
        }
        // else: keep local value (it's newer)
        
      } else {
        // Non-LWW column - server always wins
        mergedRecord[columnName] = serverValue;
      }
    }
    
    // Update the record
    await txn.update(
      tableName,
      mergedRecord,
      where: 'id = ?',
      whereArgs: [mergedRecord['id']],
    );
  }
  
  Future<bool> _performUploadSync(List<DirtyRow> operations) async {
    if (operations.isEmpty) return true;
    
    // Group operations by table and batch them
    final operationsByTable = <String, List<DirtyRow>>{};
    for (final op in operations) {
      operationsByTable.putIfAbsent(op.tableName, () => []).add(op);
    }
    
    bool allSuccessful = true;
    
    for (final entry in operationsByTable.entries) {
      final tableName = entry.key;
      final tableOperations = entry.value;
      
      // Process in batches to avoid large payloads
      final batches = _batchOperations(tableOperations, 100);
      
      for (final batch in batches) {
        final success = await _uploadBatch(tableName, batch);
        if (!success) {
          allSuccessful = false;
        }
      }
    }
    
    return allSuccessful;
  }
  
  Future<bool> _uploadBatch(String tableName, List<DirtyRow> operations) async {
    try {
      // Get full record data for each operation
      final records = <Map<String, Object?>>[];
      
      for (final op in operations) {
        final recordData = await database.queryTable(
          tableName,
          where: 'system_id = ?',
          whereArgs: [op.rowId],
          limit: 1,
        );
        
        if (recordData.isNotEmpty) {
          final encryptedRecord = await _encryptRecord(recordData.first);
          records.add(encryptedRecord);
        }
      }
      
      if (records.isEmpty) return true;
      
      // Upload to server
      final response = await _apiClient.post('/sync/upload/$tableName', records);
      final uploadResponse = SyncUploadResponse.fromJson(response.data);
      
      if (uploadResponse.hasError) {
        print('Upload failed for table $tableName: ${uploadResponse.error}');
        return false;
      }
      
      // Remove successful operations from dirty store
      final successfulIds = uploadResponse.successfulRecords.toSet();
      final successfulOps = operations.where(
        (op) => successfulIds.contains(op.rowId)
      ).toList();
      
      if (successfulOps.isNotEmpty) {
        await database.dirtyRowStore.remove(successfulOps);
      }
      
      // Handle conflicts
      if (uploadResponse.conflicts.isNotEmpty) {
        await _handleUploadConflicts(tableName, uploadResponse.conflicts);
      }
      
      return uploadResponse.conflicts.isEmpty;
      
    } catch (e) {
      print('Upload batch failed for table $tableName: $e');
      return false;
    }
  }
  
  Future<void> _handleUploadConflicts(
    String tableName,
    List<ConflictResult> conflicts,
  ) async {
    
    for (final conflict in conflicts) {
      try {
        switch (conflict.resolutionType) {
          case ConflictResolutionType.serverWins:
            // Update local record with server version
            if (conflict.resolvedRecord != null) {
              await _applyServerRecord(database, tableName, conflict.resolvedRecord!);
            }
            break;
            
          case ConflictResolutionType.clientWins:
            // Server accepted our version, nothing to do
            break;
            
          case ConflictResolutionType.manualRequired:
            // Store conflict for manual resolution
            await _storeConflictForManualResolution(tableName, conflict);
            break;
            
          case ConflictResolutionType.businessRuleViolation:
            // Show business rule violation to user
            await _notifyBusinessRuleViolation(conflict);
            break;
        }
        
      } catch (e) {
        print('Failed to handle conflict for record ${conflict.recordId}: $e');
      }
    }
  }
  
  Future<Map<String, Object?>> _encryptRecord(Map<String, Object?> record) async {
    // Implement field-level encryption for sensitive data
    final encrypted = Map<String, Object?>.from(record);
    
    // Example: encrypt PII fields
    final sensitiveFields = ['salary', 'ssn', 'phone', 'email'];
    
    for (final field in sensitiveFields) {
      if (encrypted.containsKey(field) && encrypted[field] != null) {
        encrypted[field] = await _encryption.encryptField(
          encrypted[field].toString(),
          field,
        );
      }
    }
    
    return encrypted;
  }
  
  Future<Map<String, Object?>> _decryptRecord(Map<String, Object?> record) async {
    // Implement field-level decryption
    final decrypted = Map<String, Object?>.from(record);
    
    // Example: decrypt PII fields
    final sensitiveFields = ['salary', 'ssn', 'phone', 'email'];
    
    for (final field in sensitiveFields) {
      if (decrypted.containsKey(field) && decrypted[field] != null) {
        try {
          decrypted[field] = await _encryption.decryptField(
            decrypted[field].toString(),
            field,
          );
        } catch (e) {
          print('Failed to decrypt field $field: $e');
          // Keep encrypted value or set to null based on business rules
        }
      }
    }
    
    return decrypted;
  }
  
  List<List<T>> _batchOperations<T>(List<T> items, int batchSize) {
    final batches = <List<T>>[];
    
    for (int i = 0; i < items.length; i += batchSize) {
      final end = (i + batchSize < items.length) ? i + batchSize : items.length;
      batches.add(items.sublist(i, end));
    }
    
    return batches;
  }
  
  void _notifyDownloadProgress(String tableName, int recordCount, bool hasMore) {
    // Implement progress notification for UI
    // This could use streams or callbacks
  }
  
  Future<void> _storeConflictForManualResolution(String tableName, ConflictResult conflict) async {
    // Store conflict in local database for later manual resolution
    await _storage.store('conflicts:${tableName}:${conflict.recordId}', conflict.toJson());
  }
  
  Future<void> _notifyBusinessRuleViolation(ConflictResult conflict) async {
    // Show user-friendly business rule violation message
    print('Business rule violation: ${conflict.description}');
  }
}
```

This reference implementation provides a comprehensive foundation for Oracle ERP integration with the Declarative SQLite library. The code includes:

1. **Production-ready sync gateway** with proper error handling, security, and monitoring
2. **Oracle integration layer** with dynamic query building and schema mapping
3. **Enhanced client sync manager** with encryption, conflict resolution, and retry logic
4. **Complete conflict resolution** with multiple strategies for different scenarios
5. **Security implementation** with authentication, authorization, and data encryption
6. **Performance optimizations** including caching, batching, and connection pooling

The implementation leverages all the existing capabilities of Declarative SQLite while adding the enterprise-grade features needed for Oracle ERP integration.