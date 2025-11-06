import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProfileImagePicker extends StatefulWidget {
  final String? currentImageUrl;
  final String storagePath;
  final Function(String url) onImageSelected;
  final double size;
  
  const ProfileImagePicker({
    super.key,
    this.currentImageUrl,
    required this.storagePath,
    required this.onImageSelected,
    this.size = 120,
  });

  @override
  State<ProfileImagePicker> createState() => _ProfileImagePickerState();
}

class _ProfileImagePickerState extends State<ProfileImagePicker> {
  bool _uploading = false;
  String? _error;

  Future<void> _pickAndUploadImage() async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );

      if (image == null) return;

      setState(() {
        _uploading = true;
        _error = null;
      });

      final filename = DateTime.now().millisecondsSinceEpoch.toString();
      final ext = image.name.split('.').last;
      final ref = FirebaseStorage.instance
          .ref()
          .child(widget.storagePath)
          .child('$filename.$ext');

      final metadata = SettableMetadata(
        contentType: 'image/${ext == 'jpg' ? 'jpeg' : ext}',
        cacheControl: 'public, max-age=3600',
      );

      try {
        // refresh token to avoid expired auth causing unauthorized error
        try {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) await user.getIdToken(true);
        } catch (_) {}

        final uploadTask = await ref.putFile(File(image.path), metadata);
        final url = await uploadTask.ref.getDownloadURL();

        await widget.onImageSelected(url);
      } on FirebaseException catch (e) {
        setState(() => _error = 'Upload failed (${e.code}): ${e.message ?? ''}');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _uploading ? null : _pickAndUploadImage,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant,
              shape: BoxShape.circle,
              image: widget.currentImageUrl != null
                  ? DecorationImage(
                      image: NetworkImage(widget.currentImageUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: _uploading
                ? const Center(child: CircularProgressIndicator())
                : widget.currentImageUrl == null
                    ? Icon(
                        Icons.add_a_photo_outlined,
                        size: widget.size * 0.4,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : Stack(
                        alignment: Alignment.center,
                        children: [
                          if (_uploading)
                            Container(
                              color: Colors.black38,
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            )
                          else
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black26,
                              ),
                              child: Icon(
                                Icons.edit,
                                size: widget.size * 0.3,
                                color: Colors.white,
                              ),
                            ),
                        ],
                      ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}