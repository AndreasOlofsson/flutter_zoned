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
  void buildScope(Element context, [VoidCallback? callback]) {
    if (context !=
        WidgetsFlutterBinding.ensureInitialized().renderViewElement) {
      return super.buildScope(context, callback);
    }

    if (_currentZonedTree != null) {
      _currentZonedTree!.widget.zone.run(
        () => super.buildScope(_currentZonedTree!, callback),
      );

      SchedulerBinding.instance.addPostFrameCallback(_buildZonedTrees);
    } else {
      super.buildScope(context, callback);
    }
  }

  @override
  void scheduleBuildFor(Element element) {
    final zonedAncestor = element
        .debugGetDiagnosticChain()
        .skip(1)
        .firstWhereOrNull((ancestor) => ancestor is _ZonedElement);

    if (zonedAncestor is _ZonedElement) {
      if (_currentZonedTree != zonedAncestor) {
        // ignore: prefer_collection_literals
        (_zonedDirtyLists[zonedAncestor] ??= LinkedHashSet()).add(element);

        if (!_zonedBuildScheduled) {
          _zonedBuildScheduled = true;
          if (!zonedAncestor.dirty) {
            zonedAncestor.markNeedsBuild();
          }
          SchedulerBinding.instance.addPostFrameCallback(_buildZonedTrees);
        }

        return;
      }
    } else if (_currentZonedTree != null) {
      _queuedScheduleBuildFor.add(element);
      return;
    }

    super.scheduleBuildFor(element);
  }

  bool _zonedBuildScheduled = false;
  void _buildZonedTrees(_) {
    final zonedElement = _zonedDirtyLists.keys.firstOrNull;
    if (zonedElement == null) {
      _currentZonedTree = null;
      for (final element in _queuedScheduleBuildFor) {
        if (element.debugIsActive && element.dirty) {
          super.scheduleBuildFor(element);
        }
      }
      _queuedScheduleBuildFor.clear();
      _zonedBuildScheduled = false;
    } else {
      _currentZonedTree = zonedElement;
      for (final element in _zonedDirtyLists[zonedElement]!) {
        if (element.debugIsActive && element.dirty) {
          super.scheduleBuildFor(element);
        }
      }
    }
  }

  final Map<_ZonedElement, LinkedHashSet<Element>> _zonedDirtyLists = {};
  _ZonedElement? _currentZonedTree;
  final List<Element> _queuedScheduleBuildFor = [];
}
