import 'package:flutter/widgets.dart';
import 'map_scene.dart';
import 'map_camera_controller.dart';

typedef EmergencyMapBuilder =
    Widget Function({
      required MapScene scene,
      required ValueChanged<MapCameraController> onReady,
      required ValueChanged<MapCameraEvent> onCameraIdle,
      required ValueChanged<String> onHospitalSelected,
    });
