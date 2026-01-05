import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:form_analyzer/main.dart';

void main() {
  test('calculateJointAngle returns 180 degrees for a straight line', () {
    final angle = calculateJointAngle(
      const Offset(-1, 0),
      const Offset(0, 0),
      const Offset(1, 0),
    );
    expect(angle, closeTo(180, 0.001));
  });

  test('calculateJointAngle returns 90 degrees for right angle', () {
    final angle = calculateJointAngle(
      const Offset(0, 1),
      const Offset(0, 0),
      const Offset(1, 0),
    );
    expect(angle, closeTo(90, 0.001));
  });

  test('calculateJointAngle handles acute angles', () {
    final angle = calculateJointAngle(
      const Offset(0, 1),
      const Offset(0, 0),
      const Offset(1, 1),
    );
    expect(angle, greaterThan(0));
    expect(angle, lessThan(135));
  });
}
