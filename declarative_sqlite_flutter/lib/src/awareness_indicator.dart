import 'package:flutter/material.dart';
import 'awareness_manager.dart';

/// Microsoft Office-style awareness indicator showing who's currently viewing
/// Displays semi-stacked circles with initials, max 2 visible + "+N" suffix
class AwarenessIndicator extends StatelessWidget {
  const AwarenessIndicator({
    Key? key,
    required this.users,
    this.size = 32.0,
    this.maxVisible = 2,
    this.spacing = 16.0,
    this.showTooltip = true,
    this.borderWidth = 2.0,
  }) : super(key: key);

  final List<AwarenessUser> users;
  final double size;
  final int maxVisible;
  final double spacing;
  final bool showTooltip;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return const SizedBox.shrink();
    }

    final widget = _buildIndicator(context);
    
    if (!showTooltip) {
      return widget;
    }
    
    return Tooltip(
      message: _getTooltipMessage(),
      child: widget,
    );
  }

  Widget _buildIndicator(BuildContext context) {
    final visibleUsers = users.take(maxVisible).toList();
    final extraCount = users.length - maxVisible;
    
    final children = <Widget>[];
    
    // Add user avatars
    for (int i = 0; i < visibleUsers.length; i++) {
      final user = visibleUsers[i];
      final isLast = i == visibleUsers.length - 1;
      
      children.add(
        Positioned(
          left: i * spacing,
          child: _buildUserAvatar(user, isLast && extraCount > 0 ? extraCount : null),
        ),
      );
    }
    
    // Calculate total width needed
    final totalWidth = (visibleUsers.length - 1) * spacing + size;
    
    return SizedBox(
      width: totalWidth,
      height: size,
      child: Stack(
        children: children,
      ),
    );
  }

  Widget _buildUserAvatar(AwarenessUser user, int? extraCount) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color(user.displayColor),
        border: Border.all(
          color: Colors.white,
          width: borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: extraCount != null && extraCount > 0
            ? Text(
                '+$extraCount',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.3,
                  fontWeight: FontWeight.bold,
                ),
              )
            : Text(
                user.displayInitials,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.4,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  String _getTooltipMessage() {
    if (users.isEmpty) return 'No one else viewing';
    if (users.length == 1) return '${users.first.name} is viewing';
    
    final names = users.map((u) => u.name).toList();
    if (names.length <= 3) {
      final lastUser = names.removeLast();
      return '${names.join(', ')} and $lastUser are viewing';
    } else {
      return '${names.take(2).join(', ')} and ${names.length - 2} others are viewing';
    }
  }
}

/// Compact version of awareness indicator for use in dense layouts
class CompactAwarenessIndicator extends StatelessWidget {
  const CompactAwarenessIndicator({
    Key? key,
    required this.users,
    this.size = 24.0,
    this.maxVisible = 3,
    this.spacing = 12.0,
  }) : super(key: key);

  final List<AwarenessUser> users;
  final double size;
  final int maxVisible;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return const SizedBox.shrink();
    }

    return AwarenessIndicator(
      users: users,
      size: size,
      maxVisible: maxVisible,
      spacing: spacing,
      borderWidth: 1.5,
    );
  }
}

/// Stream-based awareness indicator that automatically updates
class ReactiveAwarenessIndicator extends StatelessWidget {
  const ReactiveAwarenessIndicator({
    Key? key,
    required this.awarenessManager,
    required this.context,
    this.size = 32.0,
    this.maxVisible = 2,
    this.spacing = 16.0,
    this.showTooltip = true,
    this.placeholder,
  }) : super(key: key);

  final AwarenessManager awarenessManager;
  final AwarenessContext context;
  final double size;
  final int maxVisible;
  final double spacing;
  final bool showTooltip;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AwarenessUser>>(
      stream: awarenessManager.getAwarenessStream(this.context),
      initialData: awarenessManager.getAwarenessUsers(this.context),
      builder: (context, snapshot) {
        final users = snapshot.data ?? [];
        
        if (users.isEmpty && placeholder != null) {
          return placeholder!;
        }
        
        return AwarenessIndicator(
          users: users,
          size: size,
          maxVisible: maxVisible,
          spacing: spacing,
          showTooltip: showTooltip,
        );
      },
    );
  }
}

/// A badge-style awareness indicator showing just the count
class AwarenessBadge extends StatelessWidget {
  const AwarenessBadge({
    Key? key,
    required this.users,
    this.backgroundColor = Colors.blue,
    this.textColor = Colors.white,
    this.size = 20.0,
  }) : super(key: key);

  final List<AwarenessUser> users;
  final Color backgroundColor;
  final Color textColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor,
      ),
      child: Center(
        child: Text(
          '${users.length}',
          style: TextStyle(
            color: textColor,
            fontSize: size * 0.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// Awareness indicator with custom layout - shows users in a row
class HorizontalAwarenessIndicator extends StatelessWidget {
  const HorizontalAwarenessIndicator({
    Key? key,
    required this.users,
    this.avatarSize = 28.0,
    this.spacing = 8.0,
    this.maxVisible = 4,
    this.showNames = false,
  }) : super(key: key);

  final List<AwarenessUser> users;
  final double avatarSize;
  final double spacing;
  final int maxVisible;
  final bool showNames;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return const SizedBox.shrink();
    }

    final visibleUsers = users.take(maxVisible).toList();
    final extraCount = users.length - maxVisible;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...visibleUsers.map((user) => Padding(
          padding: EdgeInsets.only(right: spacing),
          child: _buildUserAvatar(user),
        )),
        if (extraCount > 0)
          Container(
            width: avatarSize,
            height: avatarSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey[600],
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: Center(
              child: Text(
                '+$extraCount',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: avatarSize * 0.3,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        if (showNames && users.isNotEmpty) ...[
          SizedBox(width: spacing),
          Text(
            users.length == 1
                ? users.first.name
                : '${users.length} viewing',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Widget _buildUserAvatar(AwarenessUser user) {
    return Container(
      width: avatarSize,
      height: avatarSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color(user.displayColor),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Center(
        child: Text(
          user.displayInitials,
          style: TextStyle(
            color: Colors.white,
            fontSize: avatarSize * 0.4,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}