import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Keep user-picked pictures in the app's private files directory. Android's
/// picker cache path is temporary and must never be persisted as-is.
class MedicationPhotoStorage {
  const MedicationPhotoStorage();

  Future<String> store(String path) async {
    final source = File(path);
    if (!await source.exists()) {
      throw StateError('عکس انتخاب‌شده دیگر در دسترس نیست.');
    }
    if (await source.length() > 8 * 1024 * 1024) {
      throw StateError('عکس باید کوچک‌تر از 8 مگابایت باشد.');
    }
    final root = await getApplicationSupportDirectory();
    final target = Directory('${root.path}/medication_photos');
    await target.create(recursive: true);
    if (source.absolute.path.startsWith('${target.absolute.path}/')) {
      return source.absolute.path;
    }
    final extension = path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final copied = await source.copy('${target.path}/${Uuid().v4()}.$extension');
    return copied.path;
  }
}
