import 'dart:convert';

import 'package:http/http.dart' as http;

import '../model/live_stream_model.dart';
import '../model/post_model.dart';
import 'api_service.dart';

class PostService {
  // ---------- Home feed ----------

  // The suggested feed. On page 1 the "live now" section sits after the
  // first post. [hasMore] tells the screen to ask for the next page.
  static Future<({List<FeedItem> items, bool hasMore})> getFeed({
    int page = 1,
    int perPage = 10,
  }) async {
    final response = await ApiService.get('/posts/feed', query: {
      'page': page.toString(),
      'per_page': perPage.toString(),
    });
    final data = response['data'];

    final items = <FeedItem>[];
    for (var item in data['items']) {
      if (item['type'] == 'live_section') {
        final streams = <LiveStreamModel>[];
        for (var s in item['streams']) {
          streams.add(LiveStreamModel.fromJson(s));
        }
        if (streams.isNotEmpty) items.add(FeedItem.live(streams));
      } else {
        items.add(FeedItem.post(PostModel.fromJson(item['post'])));
      }
    }
    return (items: items, hasMore: data['has_more'] == true);
  }

  // ---------- Posts ----------

  // Creates a post. The caption and the pictures are both optional, but at
  // least one of them is needed. Pictures are sent as multipart/form-data.
  static Future<PostModel> createPost({
    String caption = '',
    List<String> imagePaths = const [],
  }) async {
    await ApiService.ensureSession(); // renews an expired token first
    final token = await ApiService.getAccessToken();
    if (token == null) {
      throw ApiException('Session expired.',
          statusCode: 401, errorCode: 'session_expired', sessionExpired: true);
    }

    final request =
        http.MultipartRequest('POST', Uri.parse('${ApiService.baseUrl}/posts'));
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['Accept'] = 'application/json';
    request.fields['caption'] = caption;
    for (final path in imagePaths) {
      request.files.add(await http.MultipartFile.fromPath('images', path));
    }

    http.Response response;
    try {
      final streamed =
          await request.send().timeout(const Duration(seconds: 120));
      response = await http.Response.fromStream(streamed);
    } catch (e) {
      throw ApiException(
          'Could not reach the server. Check your internet connection.');
    }

    Map<String, dynamic> json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw ApiException('The server sent an unexpected response.',
          statusCode: response.statusCode);
    }
    final ok = response.statusCode >= 200 && response.statusCode < 300;
    if (!ok || json['success'] == false) {
      throw ApiException(
        json['message'] ?? 'Something went wrong.',
        statusCode: response.statusCode,
        errorCode: json['error_code'],
      );
    }
    return PostModel.fromJson(json['data']);
  }

  static Future<void> deletePost({required int postId}) async {
    await ApiService.delete('/posts/$postId');
  }

  // ---------- Likes ----------

  // Both return the real like count from the server.
  static Future<int> likePost({required int postId}) async {
    final response = await ApiService.post('/posts/$postId/like');
    return response['data']['like_count'] as int;
  }

  static Future<int> unlikePost({required int postId}) async {
    final response = await ApiService.delete('/posts/$postId/like');
    return response['data']['like_count'] as int;
  }

  // ---------- Comments ----------

  // Newest first.
  static Future<({List<PostCommentModel> comments, bool hasMore})> getComments({
    required int postId,
    int page = 1,
    int perPage = 20,
  }) async {
    final response = await ApiService.get('/posts/$postId/comments', query: {
      'page': page.toString(),
      'per_page': perPage.toString(),
    });
    final data = response['data'];
    final comments = <PostCommentModel>[];
    for (var item in data['comments']) {
      comments.add(PostCommentModel.fromJson(item));
    }
    return (comments: comments, hasMore: data['has_more'] == true);
  }

  static Future<PostCommentModel> addComment({
    required int postId,
    required String text,
  }) async {
    final response =
        await ApiService.post('/posts/$postId/comments', body: {'text': text});
    return PostCommentModel.fromJson(response['data']);
  }
}
