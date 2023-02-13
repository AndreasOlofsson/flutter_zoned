// flutter_zoned
// Copyright (C) 2023  Andreas Olofsson
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; version 2.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program; if not, write to the Free Software Foundation, Inc.,
// 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zoned/flutter_zoned.dart';

void main() {
  ZonedTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Runs builder body in zone', (tester) async {
    const zoneValue = #test_runs_builder_body_in_zone;

    final zone = Zone.current.fork(
      zoneValues: {
        #zoneValue: zoneValue,
      },
    );

    runApp(
      Zoned(
        zone: zone,
        child: Builder(
          builder: (context) {
            assert(Zone.current[#zoneValue] == zoneValue);
            return const Placeholder();
          },
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(Placeholder), findsOneWidget);
  });

  testWidgets('Builds child in zone', (tester) async {
    const zoneValue = #test_builds_child_in_zone;

    final zone = Zone.current.fork(
      zoneValues: {
        #zoneValue: zoneValue,
      },
    );

    runApp(
      Zoned(
        zone: zone,
        child: const AssertZoneValue(
          zoneValueKey: #zoneValue,
          zoneValue: zoneValue,
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(AssertZoneValue), findsOneWidget);
  });

  testWidgets('Rebuilds child in zone', (tester) async {
    const zoneValue = #test_rebuilds_child_in_zone;

    final zone = Zone.current.fork(
      zoneValues: {
        #zoneValue: zoneValue,
      },
    );

    final completer = Completer<bool>();

    runApp(
      Zoned(
        zone: zone,
        child: FutureBuilder(
          future: completer.future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Placeholder();
            }
            return const AssertZoneValue(
              zoneValueKey: #zoneValue,
              zoneValue: zoneValue,
            );
          },
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(Placeholder), findsOneWidget);

    completer.complete(true);

    await tester.pumpAndSettle();
    expect(find.byType(AssertZoneValue), findsOneWidget);
  });
}

class AssertZoneValue extends StatelessWidget {
  final Object zoneValueKey;
  final Object zoneValue;

  const AssertZoneValue({
    required this.zoneValueKey,
    required this.zoneValue,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    assert(Zone.current[zoneValueKey] == zoneValue);
    return Container();
  }
}
