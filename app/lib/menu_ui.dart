import 'package:flutter/material.dart';

import 'background.dart';
import 'crony_ui.dart';
import 'menu.dart';
import 'ratings.dart';
import 'site.dart';
import 'theme.dart';
import 'ui_common.dart';
import 'motion.dart';
import 'glass.dart';

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday'
];

IconData _mealIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('break')) return Icons.free_breakfast_outlined;
  if (n.contains('snack') || n.contains('tea')) return Icons.coffee_outlined;
  if (n.contains('dinner')) return Icons.dinner_dining_outlined;
  return Icons.lunch_dining_outlined;
}

String _dayName(DateTime d, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final n = DateTime(d.year, d.month, d.day).difference(today).inDays;
  if (n == 0) return 'Today';
  if (n == 1) return 'Tomorrow';
  return _weekdays[d.weekday - 1];
}

/// The next meal, for the home screen. Hidden when there is no menu.
class MenuCard extends StatelessWidget {
  const MenuCard({super.key, required this.store, required this.onChanged});
  final Store store;

  /// Favourites were changed on the menu screen.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final now = DateTime.now();
    final days = store.menu;
    final favs = store.favDishes;
    final next = nextMeal(days, now);
    final later = next == null ? firstMenuDay(days, now) : null;
    if (next == null && later == null) return const SizedBox.shrink();
    Future<void> open() async {
      await Navigator.push(
          context, MaterialPageRoute(builder: (_) => MenuScreen(store: store)));
      onChanged();
    }

    // The menu starts on a later day: say so and lead to it.
    final (icon, title, body) = next == null
        ? (
            Icons.restaurant_menu_outlined,
            'Menu from ${fmtDate(later!.date)}',
            'The next menu is up. Tap to see every day.'
          )
        : (
            _mealIcon(next.$2.name),
            '${next.$2.name} · ${_dayName(next.$1.date, now)}',
            next.$2.items.join(' · ')
          );
    final ratings = ratingsOf(store.prefs);
    final ask = mealToRate(days, now);
    final ends = bestAndWorst(ratings);
    final line = t.colorScheme.outlineVariant.withOpacity(0.5);
    final liked = next == null
        ? const <String>[]
        : [
            for (final i in next.$2.items)
              if (isFavourite(i, favs)) i
          ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('Mess menu',
          trailing: InkWell(
            onTap: open,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text('Whole week',
                  style: t.textTheme.labelLarge
                      ?.copyWith(color: t.colorScheme.primary)),
            ),
          )),
      TiltCard(
        clipBehavior: Clip.antiAlias,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: open,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                IconTile(icon),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2)),
                        const SizedBox(height: 8),
                        if (next == null)
                          Text(body,
                              style: t.textTheme.bodyMedium?.copyWith(
                                  color: t.colorScheme.onSurfaceVariant))
                        else
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            for (final i in next.$2.items)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                    color: liked.contains(i)
                                        ? t.colorScheme.primary
                                        : t.colorScheme.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(99)),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (liked.contains(i)) ...[
                                        Icon(Icons.favorite,
                                            size: 13,
                                            color: t.colorScheme.onPrimary),
                                        const SizedBox(width: 5),
                                      ],
                                      Text(i,
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: liked.contains(i)
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                              color: liked.contains(i)
                                                  ? t.colorScheme.onPrimary
                                                  : t.colorScheme.onSurface)),
                                    ]),
                              ),
                          ]),
                        if (ends != null) ...[
                          const SizedBox(height: 10),
                          Text(tasteLine(ends.$1, ends.$2),
                              style: TextStyle(
                                  fontSize: 13,
                                  color: t.colorScheme.onSurfaceVariant)),
                        ],
                      ]),
                ),
              ]),
            ),
          ),
          if (ask != null) ...[
            Divider(height: 1, thickness: 1, color: line),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
              child: RateRow(
                  store: store,
                  day: ask.$1.date,
                  meal: ask.$1.meals[ask.$2].name,
                  onRated: onChanged),
            ),
          ],
        ]),
      ),
    ]);
  }
}

const _short = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
String _mealOn(MealRating r) =>
    '${_short[r.day.weekday - 1]} ${r.meal.toLowerCase()}';

/// "Best this week: Tue dinner. Worst: Mon breakfast."
String tasteLine(MealRating best, MealRating worst) =>
    'Best this week: ${_mealOn(best)}. Worst: ${_mealOn(worst)}.';

/// "How was lunch?" with three faces; one tap rates the meal, another
/// changes the rating. Once rated it shows what everyone said.
class RateRow extends StatefulWidget {
  const RateRow(
      {super.key,
      required this.store,
      required this.day,
      required this.meal,
      this.named = false,
      this.onRated});
  final Store store;
  final DateTime day;
  final String meal;

  /// In a list of meals: lead with the meal's name instead of a question.
  final bool named;
  final VoidCallback? onRated;

  @override
  State<RateRow> createState() => _RateRowState();
}

class _RateRowState extends State<RateRow> {
  bool _busy = false;

  Future<void> _rate(int score) async {
    if (_busy) return;
    setState(() => _busy = true);
    tick();
    try {
      await rateMeal(widget.store.prefs, widget.day, widget.meal, score);
      widget.onRated?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$e'.startsWith('Exception: ')
                ? '$e'.substring(11)
                : 'No connection. The rating was not sent.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final r = ratingFor(ratingsOf(widget.store.prefs), widget.day, widget.meal);
    final mine = r?.mine;
    final said = mine == null || r == null
        ? null
        : '${scoreWord(r.average)} · ${r.count} rated';
    return Row(children: [
      Expanded(
        child: Text(
            widget.named
                ? (said == null ? widget.meal : '${widget.meal} · $said')
                : said ?? 'How was ${widget.meal.toLowerCase()}?',
            style: TextStyle(
                fontSize: 14,
                fontWeight: mine == null ? FontWeight.w600 : FontWeight.w400,
                color: mine == null
                    ? t.colorScheme.onSurface
                    : t.colorScheme.onSurfaceVariant)),
      ),
      for (var i = 0; i < 3; i++)
        Semantics(
          button: true,
          selected: mine == i + 1,
          label: scoreWords[i],
          excludeSemantics: true,
          child: InkResponse(
            radius: 24,
            onTap: _busy ? null : () => _rate(i + 1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: easeOut,
              width: 42,
              height: 42,
              margin: const EdgeInsets.only(left: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: mine == i + 1 ? Brand.lemon : Colors.transparent,
                  border: Border.all(
                      width: 1.5,
                      color: mine == i + 1 ? Brand.edge : Colors.transparent)),
              child: Opacity(
                  opacity: mine == null || mine == i + 1 ? 1 : 0.45,
                  child: CustomPaint(
                      size: const Size.square(26),
                      painter: _FacePainter(
                          i - 1,
                          mine == i + 1
                              ? Brand.onPink
                              : t.colorScheme.onSurface))),
            ),
          ),
        ),
    ]);
  }
}

/// A plain face: a frown (-1), a straight mouth (0) or a smile (1).
class _FacePainter extends CustomPainter {
  const _FacePainter(this.mouth, this.ink);
  final int mouth;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero), r = size.width / 2;
    final line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r - 1, line);
    final dot = Paint()..color = ink;
    canvas.drawCircle(c + Offset(-r * 0.36, -r * 0.2), 1.7, dot);
    canvas.drawCircle(c + Offset(r * 0.36, -r * 0.2), 1.7, dot);
    final y = c.dy + r * 0.38;
    canvas.drawPath(
        Path()
          ..moveTo(c.dx - r * 0.42, y - mouth * r * 0.08)
          ..quadraticBezierTo(c.dx, y + mouth * r * 0.34, c.dx + r * 0.42,
              y - mouth * r * 0.08),
        line);
  }

  @override
  bool shouldRepaint(_FacePainter old) => old.mouth != mouth || old.ink != ink;
}

/// Dishes people often look out for, offered as one-tap favourites.
const _suggested = [
  'Paneer',
  'Biryani',
  'Chicken',
  'Egg',
  'Ice Cream',
  'Gulab Jamun',
  'Pav Bhaji',
  'Chole Bhature',
  'Dosa',
  'Pasta',
  'Noodles',
  'Rajma',
];

/// Choose favourite dishes. Returns when the sheet is closed.
Future<void> editFavourites(BuildContext context, Store store) async {
  final input = TextEditingController();
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final t = Theme.of(ctx);
      final favs = store.favDishes;
      void save(List<String> l) {
        store.favDishes = l;
        set(() {});
        scheduleDishAlerts(store).catchError((_) {});
      }

      void add(String raw) {
        final d = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (d.isEmpty || d.length > 40) return;
        if (favs.any((f) => f.toLowerCase() == d.toLowerCase())) return;
        save([...favs, d]);
        input.clear();
      }

      return Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SheetHead('Favourite dishes',
                    subtitle: 'When one is on the menu you get a note before '
                        'that meal. A word is enough: "Paneer" covers every '
                        'paneer dish.'),
                if (favs.isNotEmpty) ...[
                  FieldLabel('Your dishes · ${favs.length}'),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    for (final f in favs)
                      InputChip(
                        label: Text(f),
                        avatar: Icon(Icons.favorite,
                            size: 16, color: t.colorScheme.primary),
                        onDeleted: () => save([
                          for (final x in favs)
                            if (x != f) x
                        ]),
                      ),
                  ]),
                  const SizedBox(height: 14),
                ],
                TextField(
                  controller: input,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onSubmitted: add,
                  decoration: InputDecoration(
                    labelText: 'Add a dish',
                    hintText: 'Paneer, Biryani, Ice Cream',
                    suffixIcon: IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () => add(input.text)),
                  ),
                ),
                const SizedBox(height: 16),
                const FieldLabel('Suggestions'),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  for (final d in _suggested)
                    if (!favs.any((f) => f.toLowerCase() == d.toLowerCase()))
                      ActionChip(label: Text(d), onPressed: () => add(d)),
                ]),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tell me before the meal'),
                  value: store.dishAlerts,
                  onChanged: (v) {
                    store.dishAlerts = v;
                    set(() {});
                    scheduleDishAlerts(store).catchError((_) {});
                  },
                ),
              ]),
        ),
      );
    }),
  );
}

/// Every published day, one page each, starting today. The coming meal is
/// raised in wine, later ones follow as cards and finished ones fold to a
/// line. Tapping any dish makes it a favourite.
class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key, required this.store});
  final Store store;

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  Store get store => widget.store;

  @override
  void initState() {
    super.initState();
    pullRatings(store.prefs).then((_) {
      if (mounted) setState(() {});
    }).catchError((_) {});
  }

  /// Tapping a dish: one that is not a favourite becomes one; one that is
  /// stops being one (with every favourite word that matched it).
  void _toggle(String item) {
    final favs = store.favDishes;
    store.favDishes = isFavourite(item, favs)
        ? [
            for (final f in favs)
              if (!isFavourite(item, [f])) f
          ]
        : [...favs, item];
    setState(() {});
    scheduleDishAlerts(store).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final days = store.menu;
    final favs = store.favDishes;
    final today = DateTime(now.year, now.month, now.day);
    final shown = [
      for (final d in days)
        if (!d.date.isBefore(today)) d
    ];
    final heart = IconButton(
      tooltip: 'Favourite dishes',
      icon: Icon(favs.isEmpty ? Icons.favorite_border : Icons.favorite),
      onPressed: () async {
        await editFavourites(context, store);
        if (mounted) setState(() {});
      },
    );
    if (shown.isEmpty) {
      return Scaffold(
          appBar: screenBar('Mess menu', actions: [heart]),
          body: const Center(
            child: EmptyNote(
                icon: Icons.restaurant_outlined,
                title: 'No menu yet',
                text: 'The menu shows here once it is published.'),
          ));
    }
    final next = nextMeal(days, now);
    final likedToday = [
      for (final m in shown.first.date == today ? shown.first.meals : <Meal>[])
        for (final i in m.items)
          if (isFavourite(i, favs)) i
    ];
    return DefaultTabController(
      length: shown.length,
      child: Scaffold(
        appBar: screenBar('Mess menu',
            subtitle: likedToday.isEmpty
                ? '${shown.length} ${shown.length == 1 ? 'day' : 'days'} published'
                : '${likedToday.length} of your favourites today',
            actions: [heart]),
        body: Column(children: [
          _DayStrip(days: shown, today: today),
          Expanded(
            child: TabBarView(children: [
              for (final d in shown)
                _dayView(context, d, today, now, next, favs),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _dayView(BuildContext context, MenuDay d, DateTime today, DateTime now,
      (MenuDay, Meal)? next, List<String> favs) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurfaceVariant;
    final nextAt = next != null && next.$1 == d ? d.meals.indexOf(next.$2) : -1;
    final isToday = d.date == today;
    final over = isToday && nextAt > 0 ? nextAt : 0;
    final later = [
      for (final (i, m) in d.meals.indexed)
        if (i >= over && i != nextAt) (i, m)
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        if (d.meals.isEmpty)
          const EmptyNote(
              icon: Icons.no_meals_outlined, title: 'No meals listed this day'),
        if (nextAt >= 0)
          Rise(
              index: 0,
              child: _NextMeal(d.meals[nextAt],
                  label: isToday && isServing(d.meals[nextAt].name, nextAt, now)
                      ? 'Serving now · till ${mealEnds(d.meals[nextAt].name, nextAt)}'
                      : 'Up next · ${mealHours(d.meals[nextAt].name, nextAt)}',
                  favs: favs,
                  onTap: _toggle)),
        if (nextAt >= 0 && later.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 10),
            child: Text(isToday ? 'Later today' : 'Later',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: muted)),
          ),
        for (final (k, (i, m)) in later.indexed)
          Rise(
              index: k + 1,
              child: _MealCard(m,
                  hours: mealHours(m.name, i), favs: favs, onTap: _toggle)),
        for (final (i, m) in d.meals.take(over).indexed)
          _OverMeal(m, hours: mealHours(m.name, i), favs: favs, onTap: _toggle),
        if (isToday &&
            [for (final i in d.meals.indexed) i.$1]
                .any((i) => canRate(d, i, now))) ...[
          const SectionTitle('How was it'),
          GroupCard(children: [
            for (final (i, m) in d.meals.indexed)
              if (canRate(d, i, now))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
                  child: RateRow(
                      store: store,
                      day: d.date,
                      meal: m.name,
                      named: true,
                      onRated: () => setState(() {})),
                ),
          ]),
          if (bestAndWorst(ratingsOf(store.prefs)) case final ends?)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
              child: Text(tasteLine(ends.$1, ends.$2),
                  style: TextStyle(fontSize: 13, color: muted)),
            ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.favorite_border, size: 15, color: muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  'Tap a dish to hear when it is on the menu. '
                  'From the mess\'s weekly menu; the mess may change a '
                  'dish on the day.',
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: muted)),
            ),
          ]),
        ),
      ],
    );
  }
}

/// The day's own dishes first, the everyday ones after. When a meal has
/// only everyday dishes, they are all treated as its own.
(List<String>, List<String>) _split(Meal m) {
  final own = [
    for (final i in m.items)
      if (!isSide(i)) i
  ];
  if (own.isEmpty) return (m.items, const <String>[]);
  return (
    own,
    [
      for (final i in m.items)
        if (isSide(i)) i
    ]
  );
}

/// The days of the menu as pills, following the swipe.
class _DayStrip extends StatelessWidget {
  const _DayStrip({required this.days, required this.today});
  final List<MenuDay> days;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = DefaultTabController.of(context);
    String label(DateTime d) {
      final n = d.difference(today).inDays;
      if (n == 0) return 'Today';
      if (n == 1) return 'Tomorrow';
      return '${_weekdays[d.weekday - 1].substring(0, 3)} ${d.day}';
    }

    return AnimatedBuilder(
      animation: c,
      builder: (context, _) => SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          children: [
            for (final (i, d) in days.indexed)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => c.animateTo(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: const Cubic(0.23, 1, 0.32, 1),
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.index == i
                          ? Brand.pink
                          : t.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(label(d.date),
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: c.index == i
                                ? Brand.onPink
                                : t.colorScheme.onSurface)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A dish that can be tapped. A favourite sits on lime with a heart.
class _Dish extends StatelessWidget {
  const _Dish(this.name,
      {required this.liked,
      required this.onTap,
      this.size = 15.5,
      this.onPink = false});
  final String name;
  final bool liked;
  final VoidCallback onTap;
  final double size;
  final bool onPink;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final ink = onPink ? Brand.onPink : t.colorScheme.onSurface;
    return Material(
      color: liked ? Brand.lemon : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: liked
              ? const EdgeInsets.fromLTRB(8, 2, 8, 3)
              : const EdgeInsets.symmetric(vertical: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (liked) ...[
              const Icon(Icons.favorite, size: 14, color: Brand.onPink),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(name,
                  style: TextStyle(
                      fontSize: size,
                      height: 1.25,
                      fontWeight: liked ? FontWeight.w700 : FontWeight.w500,
                      color: liked ? Brand.onPink : ink)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The everyday dishes as one quiet line, each still tappable.
class _Sides extends StatelessWidget {
  const _Sides(this.items,
      {required this.favs, required this.onTap, this.onPink = false});
  final List<String> items;
  final List<String> favs;
  final void Function(String) onTap;
  final bool onPink;

  @override
  Widget build(BuildContext context) {
    final muted = onPink
        ? Brand.onPink.withOpacity(0.7)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final style = TextStyle(fontSize: 13.5, height: 1.4, color: muted);
    return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 2,
        children: [
          Text('With ', style: style),
          for (final (i, x) in items.indexed)
            isFavourite(x, favs)
                ? Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _Dish(x,
                        liked: true, size: 13.5, onTap: () => onTap(x)))
                : GestureDetector(
                    onTap: () => onTap(x),
                    child: Text(
                        '${x.toLowerCase()}${i < items.length - 1 ? ', ' : ''}',
                        style: style)),
        ]);
  }
}

/// The coming meal, raised in wine so it is the first thing seen.
class _NextMeal extends StatelessWidget {
  const _NextMeal(this.m,
      {required this.label, required this.favs, required this.onTap});
  final Meal m;
  final String label;
  final List<String> favs;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    final (own, sides) = _split(m);
    return Sticker(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      radius: 24,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(_mealIcon(m.name), size: 18, color: Brand.onPink),
          const SizedBox(width: 8),
          Text(label.toUpperCase(),
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: Brand.onPink)),
        ]),
        const SizedBox(height: 6),
        Text(m.name,
            style: const TextStyle(
                fontFamily: 'Schoolbell',
                fontSize: 37,
                height: 1.1,
                fontWeight: FontWeight.w400,
                letterSpacing: 0,
                color: Brand.onPink)),
        const SizedBox(height: 12),
        for (final x in own)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _Dish(x,
                liked: isFavourite(x, favs),
                size: 19,
                onPink: true,
                onTap: () => onTap(x)),
          ),
        if (sides.isNotEmpty) ...[
          const SizedBox(height: 6),
          _Sides(sides, favs: favs, onTap: onTap, onPink: true),
        ],
      ]),
    );
  }
}

/// A meal still to come.
class _MealCard extends StatelessWidget {
  const _MealCard(this.m,
      {required this.hours, required this.favs, required this.onTap});
  final Meal m;
  final String hours;
  final List<String> favs;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final (own, sides) = _split(m);
    return TiltCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(_mealIcon(m.name), size: 18, color: muted),
            const SizedBox(width: 8),
            Text(m.name,
                style: const TextStyle(
                    fontFamily: 'Schoolbell',
                    fontSize: 20,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0)),
            const Spacer(),
            Text(hours, style: TextStyle(fontSize: 13, color: muted)),
          ]),
          const SizedBox(height: 10),
          Wrap(
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final (i, x) in own.indexed)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    _Dish(x,
                        liked: isFavourite(x, favs), onTap: () => onTap(x)),
                    if (i < own.length - 1)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        child: Text('·', style: TextStyle(color: muted)),
                      ),
                  ]),
              ]),
          if (sides.isNotEmpty) ...[
            const SizedBox(height: 8),
            _Sides(sides, favs: favs, onTap: onTap),
          ],
        ]),
      ),
    );
  }
}

/// A meal already over today: one line, opened again with a tap.
class _OverMeal extends StatefulWidget {
  const _OverMeal(this.m,
      {required this.hours, required this.favs, required this.onTap});
  final Meal m;
  final String hours;
  final List<String> favs;
  final void Function(String) onTap;

  @override
  State<_OverMeal> createState() => _OverMealState();
}

class _OverMealState extends State<_OverMeal> {
  bool open = false;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    if (open) {
      return Opacity(
        opacity: 0.6,
        child: _MealCard(widget.m,
            hours: widget.hours, favs: widget.favs, onTap: widget.onTap),
      );
    }
    final (own, _) = _split(widget.m);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => open = true),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 10),
        child: Opacity(
          opacity: 0.55,
          child: Row(children: [
            Text(widget.m.name,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Text('Over', style: TextStyle(fontSize: 13, color: muted)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(own.join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: muted)),
            ),
            Icon(Icons.expand_more, size: 18, color: muted),
          ]),
        ),
      ),
    );
  }
}
