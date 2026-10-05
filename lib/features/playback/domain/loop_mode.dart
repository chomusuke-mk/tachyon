enum Loop {
  off('off'),
  one('one'),
  all('all');

  Loop next() {
    switch (this) {
      case Loop.off:
        return Loop.all;
      case Loop.all:
        return Loop.one;
      case Loop.one:
        return Loop.off;
    }
  }

  const Loop(this.repr);
  final String repr;
  static Loop fromString(String? val) {
    return Loop.values.firstWhere((e) => e.repr == val, orElse: () => Loop.off);
  }
}
