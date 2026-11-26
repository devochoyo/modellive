import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../model/post_model.dart';
import '../../service/api_service.dart';
import '../../service/post_service.dart';
import '../../widget/common_widgets.dart';
import '../colors.dart';

// Create a post: pick pictures (optional), write a caption (optional), publish.
// At least one of the two is needed. Open it with:
//   final post = await Navigator.pushNamed(context, '/create-post');
// It returns the new PostModel when the post was published.
class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  static const int _maxImages = 10;
  static const int _maxCaption = 2000;

  final ImagePicker _picker = ImagePicker();
  final TextEditingController _caption = TextEditingController();
  final List<XFile> _images = [];
  bool _publishing = false;

  @override
  void initState() {
    super.initState();
    _caption.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  bool get _canPublish =>
      !_publishing && (_images.isNotEmpty || _caption.text.trim().isNotEmpty);

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickImages() async {
    if (_publishing) return;
    if (_images.length >= _maxImages) {
      _snack('You can add up to $_maxImages pictures.');
      return;
    }
    try {
      final picked = await _picker.pickMultiImage(
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
      if (picked.isEmpty || !mounted) return; // cancelled

      final room = _maxImages - _images.length;
      setState(() {
        for (final file in picked) {
          if (_images.length >= _maxImages) break;
          if (!_images.any((x) => x.path == file.path)) _images.add(file);
        }
      });
      if (picked.length > room) {
        _snack('Only $_maxImages pictures can be added to one post.');
      }
    } catch (e) {
      _snack('Could not open your pictures.');
    }
  }

  void _removeImage(int index) {
    if (_publishing) return;
    setState(() => _images.removeAt(index));
  }

  Future<void> _publish() async {
    if (!_canPublish) return;
    FocusScope.of(context).unfocus();
    setState(() => _publishing = true);
    try {
      final post = await PostService.createPost(
        caption: _caption.text.trim(),
        imagePaths: _images.map((x) => x.path).toList(),
      );
      if (!mounted) return;
      Navigator.pop<PostModel>(context, post);
    } on ApiException catch (e) {
      if (!e.sessionExpired) _snack(e.message);
      if (mounted) setState(() => _publishing = false);
    } catch (_) {
      _snack('Could not publish your post. Please try again.');
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.blushBackground,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: _publishing ? null : () => Navigator.pop(context),
        ),
        title: const Text(
          'Create post',
          style: TextStyle(
              color: AppColors.deepPink,
              fontWeight: FontWeight.bold,
              fontSize: 19),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('Photos', trailing: '${_images.length}/$_maxImages'),
                  const SizedBox(height: 10),
                  _photoArea(),
                  const SizedBox(height: 24),
                  _sectionTitle('Caption', trailing: 'Optional'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _caption,
                    enabled: !_publishing,
                    minLines: 5,
                    maxLines: 10,
                    maxLength: _maxCaption,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: "What's on your mind?",
                      hintStyle: const TextStyle(color: AppColors.softGrey),
                      filled: true,
                      fillColor: AppColors.white,
                      contentPadding: const EdgeInsets.all(16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(
                            color: AppColors.primaryPink, width: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Publish button (always visible at the bottom)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: BoxDecoration(
              color: AppColors.white,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryPink.withOpacity(0.12),
                  blurRadius: 12,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Opacity(
                opacity: (_canPublish || _publishing) ? 1 : 0.5,
                child: PinkButton(
                  text: 'Publish post',
                  loading: _publishing,
                  width: double.infinity,
                  onPressed: _canPublish ? _publish : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, {required String trailing}) {
    return Row(
      children: [
        Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const Spacer(),
        Text(trailing,
            style: const TextStyle(color: AppColors.softGrey, fontSize: 13)),
      ],
    );
  }

  // Empty: a big "Add photos" container. With pictures: a grid of thumbnails
  // (each with a remove button) and an "Add more" tile.
  Widget _photoArea() {
    if (_images.isEmpty) {
      return GestureDetector(
        onTap: _pickImages,
        child: Container(
          width: double.infinity,
          height: 170,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: AppColors.primaryPink.withOpacity(0.5), width: 1.5),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.softPink,
                child: Icon(Icons.add_photo_alternate_rounded,
                    color: AppColors.primaryPink, size: 30),
              ),
              SizedBox(height: 10),
              Text('Add photos',
                  style: TextStyle(
                      color: AppColors.deepPink,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
              SizedBox(height: 2),
              Text('Choose one or more from your gallery',
                  style: TextStyle(color: AppColors.softGrey, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    final showAdd = _images.length < _maxImages;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _images.length + (showAdd ? 1 : 0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemBuilder: (context, i) {
        if (i == _images.length) {
          return GestureDetector(
            onTap: _pickImages,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppColors.primaryPink.withOpacity(0.5), width: 1.5),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_rounded, color: AppColors.primaryPink, size: 30),
                  Text('Add more',
                      style: TextStyle(
                          color: AppColors.deepPink,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(File(_images[i].path), fit: BoxFit.cover),
            ),
            Positioned(
              top: 5,
              right: 5,
              child: GestureDetector(
                onTap: () => _removeImage(i),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                      color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 16),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
