// Copyright 2026 Restage Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// This file is hand-formatted.

part of 'binary.dart';

// Tags 0x40-0x5F are reserved for expression nodes; upstream keeps 0x14-0x3F.
const int _msProgram = 0x40;
const int _msEffects = 0x41;
const int _msGuard = 0x42;
const int _msNativeReference = 0x43;

String _hexTag(int type) => '0x${type.toRadixString(16).toUpperCase().padLeft(2, "0")}';

extension on _BlobDecoder {
  // Called only for tags _msProgram through _msNativeReference.
  Object _readExpressionNode(int type) {
    if (type == _msProgram) {
      return Program(_readMap(readValue)!, _readMap(_readArgument)!);
    }
    if (type == _msEffects) {
      return Effects(_readSteps());
    }
    if (type == _msGuard) {
      final Object condition = _readArgument();
      if (condition is! Program) {
        throw FormatException('Guard condition must be a program, found ${condition.runtimeType} while decoding blob.');
      }
      return Guard(condition, _readSteps());
    }
    final String key = _readString();
    final String nativeType = _readString();
    final int nullable = _readByte();
    if (nullable != _msFalse && nullable != _msTrue) {
      throw FormatException('Invalid native reference nullability ${_hexTag(nullable)} while decoding blob.');
    }
    return NativeReference(key, nativeType, nullable: nullable == _msTrue);
  }

  DynamicList _readSteps() {
    return DynamicList.generate(_readInt64(), (int index) {
      final Object step = _readArgument();
      if (step is! EventHandler && step is! SetStateHandler && step is! Guard) {
        throw FormatException('Unexpected ${step.runtimeType} in an effect sequence while decoding blob.');
      }
      return step;
    });
  }

  DynamicMap _uniqueKeys(DynamicMap map, int count) {
    if (map.length != count) {
      throw const FormatException('Duplicate key in a map while decoding blob.');
    }
    return map;
  }

  Map<Object?, Object> _uniqueCases(Map<Object?, Object> cases, int count) {
    if (cases.length != count) {
      throw const FormatException('Duplicate case in a switch while decoding blob.');
    }
    return cases;
  }
}

extension on _BlobEncoder {
  bool _writeExpressionNode(Object? value) {
    if (value is Program) {
      bytes.addByte(_msProgram);
      _writeMap(value.program, writeValue);
      _writeMap(value.captures, _writeArgument);
    } else if (value is Effects) {
      bytes.addByte(_msEffects);
      _writeSteps(value.steps);
    } else if (value is Guard) {
      bytes.addByte(_msGuard);
      _writeArgument(value.condition);
      _writeSteps(value.steps);
    } else if (value is NativeReference) {
      bytes.addByte(_msNativeReference);
      _writeString(value.key);
      _writeString(value.type);
      bytes.addByte(value.nullable ? _msTrue : _msFalse);
    } else {
      return false;
    }
    return true;
  }

  void _writeSteps(DynamicList steps) {
    _writeInt64(steps.length);
    steps.forEach(_writeArgument);
  }
}
