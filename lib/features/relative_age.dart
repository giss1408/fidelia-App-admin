/// French relative age: « à l'instant », « il y a 5 min », « il y a 3 h »,
/// « il y a 2 j ». [now] is injected so the function stays pure.
String relativeAge(DateTime created, DateTime now) {
  final diff = now.difference(created);
  if (diff.inMinutes < 1) return "à l'instant";
  if (diff.inHours < 1) return 'il y a ${diff.inMinutes} min';
  if (diff.inDays < 1) return 'il y a ${diff.inHours} h';
  return 'il y a ${diff.inDays} j';
}
