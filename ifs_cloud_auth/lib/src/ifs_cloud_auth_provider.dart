import 'package:flutter/widgets.dart';
import 'package:ifs_cloud_auth/src/ifs_cloud_auth_config.dart';

class IfsCloudAuthProvider extends StatelessWidget {
  final IfsCloudAuthConfig config;
  final Widget child;

  const IfsCloudAuthProvider({
    super.key,
    required this.config,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // Authentication logic will be added later
    return child;
  }
}
