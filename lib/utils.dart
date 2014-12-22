library dslink.utils;

import "dart:async";

class BetterIterator<T> {
  final List<T> list;

  int i = -1;

  BetterIterator(this.list);

  bool hasNext() => list.length - 1 > i + 1;

  T next() {
    i++;
    return list[i];
  }

  bool hasPrevious() => i >= 1;

  T previous() {
    i--;
    return list[i];
  }

  T current() => list[i];

  void reset() {
    i = -1;
  }
}

int currentMillis() {
  return new DateTime.now().millisecondsSinceEpoch;
}

Future waitAndRun(Duration time, action()) {
  return new Future.delayed(time, action);
}