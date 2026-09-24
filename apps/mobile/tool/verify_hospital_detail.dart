import 'dart:io';
import 'package:dio/dio.dart';
import 'package:eroute_mobile/features/hospital_detail/data/remote_hospital_detail_repository.dart';

/// Opt-in database-only smoke check. No search, NMC, or phone launcher is used.
Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln(
      'Usage: dart run tool/verify_hospital_detail.dart BASE_URL HPID [HPID...]',
    );
    exitCode = 64;
    return;
  }
  final client = Dio(
    BaseOptions(
      baseUrl: args.first,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 18),
    ),
  );
  try {
    final repository = RemoteHospitalDetailRepository(client);
    for (final hpid in args.skip(1)) {
      final detail = await repository.get(hpid);
      final basic = detail.basicInfo;
      if (basic.dataStatus != 'NOT_COLLECTED') {
        const days = [
          'MON',
          'TUE',
          'WED',
          'THU',
          'FRI',
          'SAT',
          'SUN',
          'HOLIDAY',
        ];
        if (basic.operatingHours.length != days.length ||
            !days.every(
              (day) =>
                  basic.operatingHours
                      .where((hours) => hours.day == day)
                      .length ==
                  1,
            )) {
          throw StateError('$hpid: incomplete or duplicate hospital day rows');
        }
      }
      for (final hours in basic.operatingHours) {
        if (hours.status == 'KNOWN' &&
            (hours.open == null || hours.close == null)) {
          throw StateError('$hpid: KNOWN hours require both times');
        }
      }
      stdout.writeln(
        '$hpid: parsed; address=${detail.address?.isNotEmpty == true}, '
        'mainPhone=${detail.mainPhone != null}, secondaryPhone=${detail.secondaryPhone != null}, '
        'realtime=${detail.realtimeView.coverage}, '
        'basic=${basic.dataStatus}/${basic.refreshStatus}, '
        'departments=${basic.departments.length}, '
        'hospitalDays=${basic.operatingHours.length}, stale=${basic.stale}',
      );
    }
  } finally {
    client.close();
  }
}
