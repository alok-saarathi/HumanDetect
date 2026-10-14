import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('com.saarathifinance.humandetect/gallery');

/// True when the `image` package can decode these bytes directly (JPEG, PNG, GIF,
/// WebP, BMP). Anything else, notably HEIC, is transcoded on the phone first.
bool galleryBytesAreDirectlyDecodable(Uint8List bytes) {
  if (bytes.length < 12) return false;
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) return true; // JPEG
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return true; // PNG
  }
  if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
    return true; // GIF
  }
  if (bytes[0] == 0x42 && bytes[1] == 0x4D) return true; // BMP
  // RIFF....WEBP
  return bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50;
}

/// Opens the Android photo picker and returns the chosen image's bytes.
/// Returns null if the user cancels. The temp file is deleted either way.
///
/// The picker grants access to that one image. The app does not request storage
/// permission and cannot browse the gallery on its own.
Future<Uint8List?> pickGalleryImage() async {
  if (!Platform.isAndroid) {
    throw UnsupportedError('Gallery pick is set up for Android only');
  }
  final path = await _channel.invokeMethod<String>('pickImage');
  if (path == null) return null;
  final file = File(path);
  try {
    final bytes = await file.readAsBytes();
    if (galleryBytesAreDirectlyDecodable(bytes)) return bytes;
    final jpegPath = await _channel.invokeMethod<String>('transcodeToJpeg', {
      'path': path,
    });
    if (jpegPath == null) {
      throw const FormatException('Could not convert the photo to JPEG');
    }
    final jpegFile = File(jpegPath);
    try {
      return await jpegFile.readAsBytes();
    } finally {
      if (jpegFile.existsSync()) await jpegFile.delete();
    }
  } finally {
    if (file.existsSync()) await file.delete();
  }
}
