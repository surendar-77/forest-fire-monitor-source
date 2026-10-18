import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
              const _NearbyAlertsTile(),
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
      // The backend service checks the request comes from an admin and
      // applies it; wait briefly for its answer.
      final request = await FirebaseFirestore.instance
          .collection('roleRequests')
          .add({
            'email': email,
            'role': _role.name,
            'requestedBy': FirebaseAuth.instance.currentUser?.uid,
            'status': 'pending',
            'createdAt': FieldValue.serverTimestamp(),
          });

      final result = await request
          .snapshots()
          .map((snapshot) => snapshot.data())
          .firstWhere((data) => data != null && data['status'] != 'pending')
          .timeout(const Duration(seconds: 30), onTimeout: () => null);

      if (!mounted) {
        return;
      }

      if (result != null && result['status'] == 'error') {
        setState(() => _error = '${result['message'] ?? 'Request failed.'}');
        return;
      }

      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result == null
                ? 'Request saved. It will be applied when the backend '
                      'service is running.'
                : '$email is now ${_role.label}. They should tap '
                      '"Refresh my permissions" or sign in again.',
          ),
        ),
      );
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

class _NearbyAlertsTile extends StatefulWidget {
  const _NearbyAlertsTile();

  @override
  State<_NearbyAlertsTile> createState() => _NearbyAlertsTileState();
}

class _NearbyAlertsTileState extends State<_NearbyAlertsTile> {
  bool _enabled = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    FcmService.nearbyAlertsEnabled().then((value) {
      if (mounted) setState(() => _enabled = value);
    });
  }

  Future<void> _toggle(bool value) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await FcmService.setNearbyAlerts(value);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _enabled = ok ? value : false;
    });
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Allow location access to get alerts about nearby fires.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(Icons.near_me_outlined),
      title: const Text('Alert me about fires near me'),
      subtitle: const Text(
        'Serious alerts from any node within 10 km of this phone. '
        "Shares this phone's location with the alert service.",
      ),
      value: _enabled,
      onChanged: _busy ? null : _toggle,
    );
  }
}
