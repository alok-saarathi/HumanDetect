import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

/// Model files bundled from assets/models/ (fetched or exported, never committed).
abstract final class ModelAssets {
  static const blazeFace = 'assets/models/blaze_face_short_range.tflite';
  static const faceMesh = 'assets/models/face_landmarks_detector.tflite';
  static const tinyClip = 'assets/models/tinyclip_image_encoder.tflite';
  static const tinyClipPrompts = 'assets/models/tinyclip_prompts.json';
}

/// Loads each model once and shares the interpreter between screens.
abstract final class ModelStore {
  static final _cache = <String, Future<Interpreter>>{};

  static Future<Interpreter> load(String asset) => _cache.putIfAbsent(
    asset,
    () => Interpreter.fromAsset(
      asset,
      options: InterpreterOptions()..threads = 4,
    ),
  );
}

extension FloatTensors on Interpreter {
  /// Copies [values] into input tensor [index]. Uses the copy API: writing the
  /// tensor pointer in place makes [Interpreter.invoke] fail on device
  /// ("Bad state: failed precondition").
  void setFloatInput(int index, Float32List values) {
    final tensor = getInputTensor(index);
    final bytes = values.buffer.asUint8List(
      values.offsetInBytes,
      values.lengthInBytes,
    );
    if (tensor.numBytes() != bytes.length) {
      throw StateError(
        'Model input is ${tensor.numBytes()} bytes, this buffer is ${bytes.length}.',
      );
    }
    tensor.setTo(bytes);
  }

  /// Copies the output tensor named [name] out as floats.
  Float32List floatOutput(String name) {
    final tensor = getOutputTensors().firstWhere(
      (t) => t.name == name,
      orElse: () => throw ArgumentError('No output tensor named $name'),
    );
    return Uint8List.fromList(tensor.data).buffer.asFloat32List();
  }

  /// Copies output tensor [index] out as floats.
  Float32List floatOutputAt(int index) =>
      Uint8List.fromList(getOutputTensor(index).data).buffer.asFloat32List();
}
