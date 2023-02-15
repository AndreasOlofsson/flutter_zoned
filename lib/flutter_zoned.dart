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

library flutter_zoned;

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class Zoned extends StatelessWidget {
  final Zone zone;
  final Widget child;

  const Zoned({required this.zone, required this.child, super.key});

  @override
  Widget build(BuildContext context) => child;

  @override
  StatelessElement createElement() => _ZonedElement(this);
}

class _ZonedElement extends StatelessElement {
  _ZonedElement(super.widget) {
    assert(
      WidgetsFlutterBinding.ensureInitialized() is _ZonedWidgetsFlutterBinding,
      "The current WidgetsFlutterBinding is not an instance of _ZonedWidgetsFlutterBinding. \n"
      "Call ZonedWidgetsFlutterBinding.ensureInitialized() or ZonedTestWidgetsFlutterBinding.ensureInitialized() "
      "at the start of your main() function to initialize the zoned binding.",
    );
  }

  @override
  Zoned get widget => super.widget as Zoned;

  @override
  void performRebuild() {
    widget.zone.run(() => super.performRebuild());
  }
}

mixin _ZonedWidgetsFlutterBinding implements WidgetsFlutterBinding {}

class ZonedWidgetsFlutterBinding extends WidgetsFlutterBinding
    with _ZonedWidgetsFlutterBinding {
  static ZonedWidgetsFlutterBinding? _instance;

  static WidgetsFlutterBinding ensureInitialized() {
    return _instance ??= ZonedWidgetsFlutterBinding._();
  }

  ZonedWidgetsFlutterBinding._() : super() {
    _buildOwner = _ZonedBuildOwner(
      onBuildScheduled: super.buildOwner!.onBuildScheduled,
      focusManager: super.buildOwner!.focusManager,
    );
  }

  @override
  BuildOwner? get buildOwner => _buildOwner ?? super.buildOwner;

  BuildOwner? _buildOwner;
}

mixin ZonedTestWidgetsFlutterBinding implements _ZonedWidgetsFlutterBinding {
  static ZonedTestWidgetsFlutterBinding ensureInitialized() {
    if (_instance != null) return _instance!;

    final environment = Platform.environment;
    if (environment.containsKey('FLUTTER_TEST') &&
        environment['FLUTTER_TEST'] != 'false') {
      return ZonedAutomatedTestWidgetsFlutterBinding.ensureInitialized();
    }
    return ZonedLiveTestWidgetsFlutterBinding.ensureInitialized();
  }

  static ZonedTestWidgetsFlutterBinding? _instance;
}

class ZonedAutomatedTestWidgetsFlutterBinding
    extends AutomatedTestWidgetsFlutterBinding
    with ZonedTestWidgetsFlutterBinding, _ZonedWidgetsFlutterBinding {
  static ZonedTestWidgetsFlutterBinding ensureInitialized() {
    return ZonedTestWidgetsFlutterBinding._instance ??=
        ZonedAutomatedTestWidgetsFlutterBinding._();
  }

  ZonedAutomatedTestWidgetsFlutterBinding._() : super() {
    _buildOwner = _ZonedBuildOwner(
      onBuildScheduled: super.buildOwner!.onBuildScheduled,
      focusManager: super.buildOwner!.focusManager,
    );
  }

  @override
  BuildOwner? get buildOwner => _buildOwner ?? super.buildOwner;

  BuildOwner? _buildOwner;
}

class ZonedLiveTestWidgetsFlutterBinding extends LiveTestWidgetsFlutterBinding
    with ZonedTestWidgetsFlutterBinding, _ZonedWidgetsFlutterBinding {
  static ZonedTestWidgetsFlutterBinding ensureInitialized() {
    return ZonedTestWidgetsFlutterBinding._instance ??=
        ZonedLiveTestWidgetsFlutterBinding._();
  }

  ZonedLiveTestWidgetsFlutterBinding._() : super() {
    _buildOwner = _ZonedBuildOwner(
      onBuildScheduled: super.buildOwner!.onBuildScheduled,
      focusManager: super.buildOwner!.focusManager,
    );
  }

  @override
  BuildOwner? get buildOwner => _buildOwner ?? super.buildOwner;

  BuildOwner? _buildOwner;
}

class _ZonedBuildOwner extends BuildOwner {
  _ZonedBuildOwner({super.onBuildScheduled, super.focusManager});

  @override
  VoidCallback? get onBuildScheduled =>
      _enableOnBuildScheduled ? super.onBuildScheduled : null;

  @override
  void buildScope(Element context, [VoidCallback? callback]) {
    if (context !=
        WidgetsFlutterBinding.ensureInitialized().renderViewElement) {
      return super.buildScope(context, callback);
    }

    super.buildScope(context, callback);

    final zonedDirtyLists = _zonedDirtyLists.entries.toList();
    _zonedDirtyLists.clear();

    for (final entry in zonedDirtyLists) {
      final zonedElement = entry.key;
      if (zonedElement.debugIsActive) {
        _currentZonedTree = zonedElement;
        for (final element in entry.value) {
          final zonedAncestor = _zonedAncestor(element);
          if (zonedAncestor != zonedElement) {
            if (zonedAncestor == null) {
              _queuedScheduleBuildFor.add(element);
            } else {
              // ignore: prefer_collection_literals
              (_zonedDirtyLists[zonedAncestor] ??= LinkedHashSet())
                  .add(element);
            }
          } else if (element.dirty) {
            _enableOnBuildScheduled = false;
            super.scheduleBuildFor(element);
            _enableOnBuildScheduled = true;
          }
        }
        zonedElement.widget.zone.run(() => super.buildScope(zonedElement));
        _currentZonedTree = null;
      }
    }

    final queuedScheduleBuildFor = _queuedScheduleBuildFor.toList();
    _queuedScheduleBuildFor.clear();

    for (final element in queuedScheduleBuildFor) {
      if (element.dirty && element.debugIsActive) {
        _enableOnBuildScheduled = false;
        super.scheduleBuildFor(element);
        _enableOnBuildScheduled = true;
      }
    }

    if (queuedScheduleBuildFor.isNotEmpty) {
      super.buildScope(context, callback);
    }
  }

  @override
  void scheduleBuildFor(Element element) {
    final zonedAncestor = _zonedAncestor(element);

    if (zonedAncestor != null) {
      if (_currentZonedTree != zonedAncestor) {
        // ignore: prefer_collection_literals
        (_zonedDirtyLists[zonedAncestor] ??= LinkedHashSet()).add(element);

        if (!zonedAncestor.dirty) {
          if (!debugBuilding) {
            zonedAncestor.markNeedsBuild();
          } else if (_currentZonedTree != zonedAncestor) {
            _queuedScheduleBuildFor.add(zonedAncestor);
          }
        }
        return;
      }
    } else if (_currentZonedTree != null) {
      _queuedScheduleBuildFor.add(element);
      return;
    }

    super.scheduleBuildFor(element);
  }

  _ZonedElement? _zonedAncestor(Element element) {
    return element
            .debugGetDiagnosticChain()
            .skip(1)
            .firstWhereOrNull((ancestor) => ancestor is _ZonedElement)
        as _ZonedElement?;
  }

  final Map<_ZonedElement, LinkedHashSet<Element>> _zonedDirtyLists = {};
  final List<Element> _queuedScheduleBuildFor = [];
  _ZonedElement? _currentZonedTree;
  bool _enableOnBuildScheduled = true;
}
