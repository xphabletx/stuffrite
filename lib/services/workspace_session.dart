import 'package:flutter/widgets.dart';

/// Provides the current workspace ID down the widget tree.
class WorkspaceSession extends InheritedWidget {
  const WorkspaceSession({
    super.key,
    required this.workspaceId,
    required super.child,
  });

  final String? workspaceId;

  static WorkspaceSession of(BuildContext ctx) =>
      ctx.dependOnInheritedWidgetOfExactType<WorkspaceSession>()!;

  @override
  bool updateShouldNotify(covariant WorkspaceSession old) =>
      old.workspaceId != workspaceId;
}
