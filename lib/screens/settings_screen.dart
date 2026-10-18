import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../services/fcm_service.dart';
import '../services/node_repository.dart';
import 'location_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.auth,
    required this.repository,
  });

  final AuthService auth;
  final NodeRepository repository;

  Future<void> _signOut(BuildContext context) async {
    final navigator = Navigator.of(context);

    await FcmService.unregister();
    await auth.signOut();

    navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AnimatedBuilder(
        animation: Listenable.merge([auth, repository]),
        builder: (context, _) {
          final user = auth.user;

          if (user == null) {
            return const SizedBox.shrink();
          }

          return ListView(
            children: [
              ListTile(
                leading: CircleAvatar(
                  child: Text(
                    user.displayName.isEmpty
                        ? '?'
                        : user.displayName[0].toUpperCase(),
                  ),
                ),
                title: Text(user.displayName),
                subtitle: Text(user.email),
                trailing: Chip(label: Text(user.role.label)),
              ),
              const Divider(),
              _sectionTitle(context, 'Alert notifications'),
              _SubscriptionTile(auth: auth, repository: repository, user: user),
              const Divider(),
              _sectionTitle(context, 'Device'),
              ListTile(
                leading: const Icon(Icons.edit_location_alt_outlined),
                title: const Text('Default map location'),
                subtitle: const Text(
                  'Used for nodes that have no saved coordinates',
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LocationSettingsScreen(),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Refresh my permissions'),
                subtitle: const Text(
                  'Use this after an administrator changes your role',
                ),
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await auth.refreshRole();
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Permissions refreshed.')),
                  );
                },
              ),
              if (auth.isAdmin) ...[
                const Divider(),
                _sectionTitle(context, 'Administration'),
                ListTile(
                  leading: const Icon(Icons.manage_accounts_outlined),
                  title: const Text('Set a user\'s role'),
                  subtitle: const Text('Viewer, officer or administrator'),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => const _SetRoleDialog(),
                  ),
                ),
              ],
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text(
                  'Sign out',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () => _signOut(context),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _SubscriptionTile extends StatelessWidget {
  const _SubscriptionTile({
    required this.auth,
    required this.repository,
    required this.user,
  });

  final AuthService auth;
  final NodeRepository repository;
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final nodes = repository.nodes;
    final subscribed = user.subscribedNodes;
    final allNodes = subscribed.isEmpty;

    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.notifications_active_outlined),
          title: const Text('Alerts from all nodes'),
          subtitle: const Text('Turn off to choose specific nodes'),
          value: allNodes,
          onChanged: (value) {
            auth.updateSubscribedNodes(
              value ? const [] : nodes.map((node) => node.id).toList(),
            );
          },
        ),
        if (!allNodes)
          for (final node in nodes)
            CheckboxListTile(
              contentPadding: const EdgeInsets.only(left: 72, right: 16),
              title: Text(node.name),
              subtitle: Text(node.zone ?? node.id),
              value: subscribed.contains(node.id),
              onChanged: (checked) {
                final next = [...subscribed];

                if (checked == true) {
                  next.add(node.id);
                } else {
                  next.remove(node.id);
                }

                // An empty list means "all nodes", so keep at least one.
                if (next.isNotEmpty) {
                  auth.updateSubscribedNodes(next);
                }
              },
            ),
      ],
    );
  }
}

class _SetRoleDialog extends StatefulWidget {
  const _SetRoleDialog();

  @override
  State<_SetRoleDialog> createState() => _SetRoleDialogState();
}

class _SetRoleDialogState extends State<_SetRoleDialog> {
  final _emailController = TextEditingController();
  UserRole _role = UserRole.officer;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();

    if (!email.contains('@')) {
      setState(() => _error = 'Enter the user\'s email address.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await FirebaseFunctions.instance.httpsCallable('setUserRole').call({
        'email': email,
        'role': _role.name,
      });

      if (!mounted) {
        return;
      }

      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '$email is now ${_role.label}. They should tap '
            '"Refresh my permissions" or sign in again.',
          ),
        ),
      );
    } on FirebaseFunctionsException catch (error) {
      setState(() => _error = error.message ?? error.code);
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set user role'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'User email',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          SegmentedButton<UserRole>(
            segments: [
              for (final role in UserRole.values)
                ButtonSegment(value: role, label: Text(role.label)),
            ],
            selected: {_role},
            onSelectionChanged: (selection) =>
                setState(() => _role = selection.first),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'SAVING...' : 'SAVE'),
        ),
      ],
    );
  }
}
