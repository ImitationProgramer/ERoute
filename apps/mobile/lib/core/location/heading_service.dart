import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HeadingReading {
  final double? degrees;
  final double? quality;
  const HeadingReading(this.degrees, this.quality);
  double? get usableDegrees {
    final value = degrees;
    final accuracy = quality;
    if (value == null ||
        !value.isFinite ||
        accuracy == null ||
        !accuracy.isFinite ||
        accuracy < 0 ||
        accuracy > 30) {
      return null;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS && value < 0) return null;
    return (value % 360 + 360) % 360;
  }
}

abstract interface class HeadingService {
  Stream<HeadingReading> watch();
}

class CompassHeadingService implements HeadingService {
  @override
  Stream<HeadingReading> watch() =>
      (FlutterCompass.events ?? const Stream<CompassEvent>.empty()).map(
        (event) => HeadingReading(event.heading, event.accuracy),
      );
}

final headingServiceProvider = Provider<HeadingService>(
  (ref) => CompassHeadingService(),
);
