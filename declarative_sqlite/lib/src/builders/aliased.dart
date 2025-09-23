class Aliased<T> {
  final T expression;
  final String? alias;

  const Aliased(this.expression, this.alias);

  @override
  String toString() {
    return alias != null ? '$expression AS $alias' : expression.toString();
  }
}
