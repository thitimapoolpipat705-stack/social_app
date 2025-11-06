import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/group_service.dart';
import '../../widgets/profile_image_picker.dart';

class EditGroupScreen extends StatefulWidget {
  final String groupId;
  
  const EditGroupScreen({super.key, required this.groupId});

  @override
  State<EditGroupScreen> createState() => _EditGroupScreenState();
}

class _EditGroupScreenState extends State<EditGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await GroupService.instance.updateGroupProfile(
        groupId: widget.groupId,
        name: _nameController.text.trim(),
        description: _descController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group updated successfully')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Group'),
        actions: [
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: CircularProgressIndicator(),
              ),
            )
          else
            IconButton(
              onPressed: _save,
              icon: const Icon(Icons.save),
              tooltip: 'Save changes',
            ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('groups')
            .doc(widget.groupId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data == null) {
            return const Center(child: Text('Group not found'));
          }

          // Update controllers if empty (first load)
          if (_nameController.text.isEmpty) {
            _nameController.text = data['name'] as String? ?? '';
          }
          if (_descController.text.isEmpty) {
            _descController.text = data['description'] as String? ?? '';
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Profile Image
                  Center(
                    child: ProfileImagePicker(
                      currentImageUrl: data['photoURL'] as String?,
                      storagePath: 'groups/${widget.groupId}/profile',
                      onImageSelected: (url) async {
                        try {
                          await GroupService.instance.updateGroupProfile(
                            groupId: widget.groupId,
                            photoURL: url,
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Profile photo updated')),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e')),
                            );
                          }
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Cover Image
                  Container(
                    height: 120,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                      image: data['coverURL'] != null
                          ? DecorationImage(
                              image: NetworkImage(data['coverURL']!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () async {
                          // Handle cover image update here
                        },
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                data['coverURL'] != null
                                    ? Icons.edit
                                    : Icons.add_photo_alternate_outlined,
                                size: 32,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                data['coverURL'] != null
                                    ? 'Change Cover Photo'
                                    : 'Add Cover Photo',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Group Name
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Group Name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Group name is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Description
                  TextFormField(
                    controller: _descController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    maxLines: 3,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}