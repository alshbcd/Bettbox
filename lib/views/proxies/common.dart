import 'package:bett_box/clash/clash.dart';
import 'package:bett_box/common/common.dart';
import 'package:bett_box/enum/enum.dart';
import 'package:bett_box/models/models.dart';
import 'package:bett_box/state.dart';

import 'package:flutter/foundation.dart';

class DelayTestCoordinator extends ChangeNotifier {
  String? _testingGroupName;

  String? get testingGroupName => _testingGroupName;

  bool get isTesting => _testingGroupName != null;

  bool isTestingGroup(String groupName) => _testingGroupName == groupName;

  Future<bool> run(String groupName, Future<void> Function() action) async {
    if (isTesting) {
      return false;
    }

    _testingGroupName = groupName;
    notifyListeners();
    try {
      await action();
      return true;
    } finally {
      _testingGroupName = null;
      notifyListeners();
    }
  }
}

final delayTestCoordinator = DelayTestCoordinator();

@immutable
class DelayTestTarget {
  final String name;
  final String url;

  const DelayTestTarget({required this.name, required this.url});

  @override
  bool operator ==(Object other) {
    return other is DelayTestTarget && other.name == name && other.url == url;
  }

  @override
  int get hashCode => Object.hash(name, url);
}

class DelayTestRequestPool {
  final Map<DelayTestTarget, Future<Delay>> _pendingRequests = {};

  int get pendingCount => _pendingRequests.length;

  Future<Delay> run(DelayTestTarget target, Future<Delay> Function() action) {
    final pendingRequest = _pendingRequests[target];
    if (pendingRequest != null) {
      return pendingRequest;
    }

    final request = action();
    _pendingRequests[target] = request;
    return request.whenComplete(() {
      if (identical(_pendingRequests[target], request)) {
        _pendingRequests.remove(target);
      }
    });
  }
}

final _delayTestRequestPool = DelayTestRequestPool();

double get listHeaderHeight {
  final measure = globalState.measure;
  return 20 + measure.titleMediumHeight + 4 + measure.bodyMediumHeight;
}

double getItemHeight(ProxyCardType proxyCardType) {
  final measure = globalState.measure;
  final baseHeight =
      16 + measure.bodyMediumHeight * 2 + measure.bodySmallHeight + 8 + 4;
  return switch (proxyCardType) {
    ProxyCardType.expand =>
      baseHeight - measure.bodySmallHeight + measure.labelSmallHeight * 2 + 4,
    ProxyCardType.shrink => baseHeight,
    ProxyCardType.min => baseHeight - measure.bodyMediumHeight,
  };
}

Future<void> proxyDelayTest(Proxy proxy, [String? testUrl]) async {
  if (_isNonTestableProxy(proxy)) return;
  final appController = globalState.appController;
  final state = appController.getProxyCardState(proxy.name);
  final url = appController.getRealTestUrl(
    state.testUrl.getSafeValue(testUrl ?? ''),
  );
  if (state.proxyName.isEmpty) {
    return;
  }
  await _testProxyDelay(DelayTestTarget(name: state.proxyName, url: url));
  appController.addSortNum();
}

Future<Delay> _testProxyDelay(DelayTestTarget target) {
  return _delayTestRequestPool.run(target, () async {
    final appController = globalState.appController;
    appController.setDelay(Delay(url: target.url, name: target.name, value: 0));
    final delay = await clashCore.getDelay(target.url, target.name);
    appController.setDelay(delay);
    return delay;
  });
}

bool _isNonTestableProxyName(String proxyName) {
  final name = proxyName.toUpperCase();
  return name == 'REJECT' || name == 'REJECT-DROP' || name == 'PASS';
}

bool _isNonTestableProxyType(String proxyType) {
  return proxyType.toUpperCase() == 'REMATCH';
}

bool _isNonTestableProxy(Proxy proxy) {
  return _isNonTestableProxyName(proxy.name) ||
      _isNonTestableProxyType(proxy.type);
}

Future<void> delayTest(
  List<Proxy> proxies, {
  String? testUrl,
  String? groupName,
  Future<void> Function()? onDelayUpdated,
}) async {
  Future<void> runTest() async {
    final appController = globalState.appController;
    final currentGroups = appController.getCurrentGroups();
    final targets = <DelayTestTarget>{};
    for (final proxy in proxies) {
      if (_isNonTestableProxy(proxy)) {
        continue;
      }
      final state = appController.getProxyCardState(proxy.name);
      final url = appController.getRealTestUrl(
        state.testUrl.getSafeValue(testUrl ?? ''),
      );
      final name = state.proxyName;
      if (name.isEmpty ||
          _isNonTestableProxyName(name) ||
          (currentGroups.getGroup(name) == null &&
              currentGroups.getRematchProxy(name) != null)) {
        continue;
      }
      targets.add(DelayTestTarget(name: name, url: url));
    }
    final concurrencyLimit = globalState.config.proxiesStyle.concurrencyLimit;

    // 按实际节点和实际测试地址创建任务，避免多个代理组别名重复测速。
    final delayTasks = targets.map((target) {
      return () async {
        await _testProxyDelay(target);
        await onDelayUpdated?.call();
      };
    }).toList();

    if (concurrencyLimit <= 1 || delayTasks.length <= 1) {
      for (final task in delayTasks) {
        await task();
      }
    } else {
      var nextIndex = 0;
      final running = <Future<void>>{};
      while (nextIndex < delayTasks.length || running.isNotEmpty) {
        while (nextIndex < delayTasks.length &&
            running.length < concurrencyLimit) {
          final task = delayTasks[nextIndex++];
          late final Future<void> future;
          future = task().whenComplete(() {
            running.remove(future);
          });
          running.add(future);
        }
        if (running.isNotEmpty) {
          await Future.any(running);
        }
      }
    }
    appController.addSortNum();
  }

  if (groupName == null || groupName.isEmpty) {
    await runTest();
    return;
  }
  await delayTestCoordinator.run(groupName, runTest);
}

Future<void> _runWithConcurrency<T>(
  List<T> items,
  int concurrency,
  Future<void> Function(T item) task,
) async {
  if (items.isEmpty) return;
  final limit = concurrency < 1 ? 1 : concurrency;
  var nextIndex = 0;
  final running = <Future<void>>{};
  while (nextIndex < items.length || running.isNotEmpty) {
    while (nextIndex < items.length && running.length < limit) {
      final item = items[nextIndex++];
      late final Future<void> future;
      future = task(item).whenComplete(() {
        running.remove(future);
      });
      running.add(future);
    }
    if (running.isNotEmpty) {
      await Future.any(running);
    }
  }
}

Future<void> _testProxySpeed(String proxyName, String? testUrl) async {
  final appController = globalState.appController;
  final state = appController.getProxyCardState(proxyName);
  final delayUrl = appController.getRealTestUrl(
    state.testUrl.getSafeValue(testUrl ?? ''),
  );

  appController.setSpeed(proxyName, -1);

  final delay = await clashCore.getDelay(delayUrl, proxyName);
  if (delay.value == null || delay.value! <= 0) {
    appController.setSpeed(proxyName, null);
    return;
  }

  try {
    final result = await clashCore.getSpeed(
      proxyName,
      globalState.config.appSetting.speedTestUrl,
    );
    appController.setSpeed(proxyName, result.speed);
  } catch (e) {
    commonPrint.warn('speed test failed [$proxyName]: $e');
    appController.setSpeed(proxyName, null);
  }
}

Future<void> proxySpeedTest(Proxy proxy, {String? testUrl}) async {
  if (_isNonTestableProxy(proxy)) return;
  final appController = globalState.appController;
  final state = appController.getProxyCardState(proxy.name);
  if (state.proxyName.isEmpty) return;
  appController.setShowSpeed(true);
  await _testProxySpeed(state.proxyName, testUrl);
  appController.addSortNum();
}

Future<void> speedTest(
  List<Proxy> proxies, {
  String? testUrl,
  String? groupName,
  Future<void> Function()? onSpeedUpdated,
}) async {
  Future<void> runTest() async {
    final appController = globalState.appController;
    appController.setShowSpeed(true);
    final concurrency = globalState.config.appSetting.speedTestConcurrency;
    final names = <String>{};
    for (final proxy in proxies) {
      if (_isNonTestableProxy(proxy)) continue;
      final state = appController.getProxyCardState(proxy.name);
      if (state.proxyName.isEmpty) continue;
      if (_isNonTestableProxyName(state.proxyName)) continue;
      names.add(state.proxyName);
    }
    await _runWithConcurrency(names.toList(), concurrency, (name) async {
      await _testProxySpeed(name, testUrl);
      await onSpeedUpdated?.call();
    });
    appController.addSortNum();
  }

  if (groupName == null || groupName.isEmpty) {
    await runTest();
    return;
  }
  await delayTestCoordinator.run(groupName, runTest);
}

double getScrollToSelectedOffset({
  required String groupName,
  required List<Proxy> proxies,
}) {
  final appController = globalState.appController;
  final columns = appController.getProxiesColumns();
  final proxyCardType = globalState.config.proxiesStyle.cardType;
  final selectedProxyName = appController.getSelectedProxyName(groupName);
  final findSelectedIndex = proxies.indexWhere(
    (proxy) => proxy.name == selectedProxyName,
  );
  final selectedIndex = findSelectedIndex != -1 ? findSelectedIndex : 0;
  final rows = (selectedIndex / columns).floor();
  return rows * getItemHeight(proxyCardType) + (rows - 1) * 8;
}
