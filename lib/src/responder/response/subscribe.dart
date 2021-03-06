part of dslink.responder;

class RespSubscribeListener {
  Function callback;
  LocalNode node;
  RespSubscribeListener(this.node, this.callback);
  void cancel(){
    if (callback != null) {
      node.unsubscribe(callback);
      callback = null;
    }
  }
}

class SubscribeResponse extends Response {
  SubscribeResponse(Responder responder, int rid) : super(responder, rid);

  final Map<String, RespSubscribeController> subsriptions =
      new Map<String, RespSubscribeController>();
  final Map<int, RespSubscribeController> subsriptionids =
      new Map<int, RespSubscribeController>();
  
  final LinkedHashSet<RespSubscribeController> changed =
      new LinkedHashSet<RespSubscribeController>();

  void add(String path, LocalNode node, int sid, int cacheLevel) {
    if (subsriptions[path] != null) {
      RespSubscribeController controller = subsriptions[path];
      if (controller.sid != sid) {
        subsriptionids.remove(controller.sid);
        controller.sid == sid;
        subsriptionids[sid] = controller;
      }
      controller.cacheLevel = cacheLevel;
    } else {
      RespSubscribeController controller =
          new RespSubscribeController(this, node, sid, cacheLevel);
      subsriptions[path] = controller;
      subsriptionids[sid] = controller;
    }
  }
  void remove(int sid) {
    if (subsriptionids[sid] != null) {
      RespSubscribeController controller = subsriptionids[sid];
      subsriptionids[sid].destroy();
      subsriptionids.remove(sid);
      subsriptions.remove(controller.node.path);
    }
  }

  void subscriptionChanged(RespSubscribeController controller) {
    changed.add(controller);
    responder.addProcessor(processor);
  }
  void processor() {
    List updates = [];
    for (RespSubscribeController controller in changed) {
      updates.addAll(controller.process());
    }
    responder.updateReponse(this, updates);
    changed.clear();
  }
  void _close() {
    subsriptions.forEach((path, controller) {
      controller.destroy();
    });
    subsriptions.clear();
  }
}

class RespSubscribeController {
  final LocalNode node;
  final SubscribeResponse response;
  RespSubscribeListener _listener;
  int sid;

  ListQueue<ValueUpdate> lastValues = new ListQueue<ValueUpdate>();

  int _cachedLevel;
  int get cacheLevel {
    return _cachedLevel;
  }
  void set cacheLevel(int v) {
    if (v < 1) v = 1;
    _cachedLevel = v;
  }
  RespSubscribeController(this.response, this.node, this.sid, int catcheLevel) {
    this.cacheLevel = catcheLevel;
    if (node.valueReady && node.lastValueUpdate != null) {
      addValue(node.lastValueUpdate);
    }
    _listener = node.subscribe(addValue, catcheLevel);
  }

  void addValue(ValueUpdate val) {
    lastValues.add(val);
    if (lastValues.length > _cachedLevel) {
      mergeValues();
    }
    // TODO, don't allow this to be called from same controller more oftern than 100ms
    // the first response can happen ASAP, but
    response.subscriptionChanged(this);
  }
  void mergeValues() {
    int toRemove = lastValues.length - _cachedLevel;
    ValueUpdate rslt = lastValues.removeFirst();
    for (int i = 0; i < toRemove; ++i) {
      rslt = new ValueUpdate.merge(rslt, lastValues.removeFirst());
    }
    lastValues.addFirst(rslt);
  }

  List process() {
    List rslts = [];
    for (ValueUpdate lastValue in lastValues) {
      if (lastValue.count > 1 || lastValue.status != null) {
        Map m = {'ts': lastValue.ts, 'value': lastValue.value, 'sid': sid};
        if (lastValue.count == 0) {} else if (lastValue.count > 1) {
          m['count'] = lastValue.count;
          if (lastValue.sum.isFinite) {
            m['sum'] = lastValue.sum;
          }
          if (lastValue.max.isFinite) {
            m['max'] = lastValue.max;
          }
          if (lastValue.min.isFinite) {
            m['min'] = lastValue.min;
          }
        }
        rslts.add(m);
      } else {
        rslts.add([sid, lastValue.value, lastValue.ts]);
      }
    }
    lastValues.clear();
    return rslts;
  }
  void destroy() {
    _listener.cancel();
  }
}
