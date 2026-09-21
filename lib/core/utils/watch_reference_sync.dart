// The phone's reference data on its way to the wrist: the lists that let the
// watch work while the phone is in another room.
//
// Plan: `.github/agents/plans/2026-07-13-12-e-watch-nutrition-quick-log-plan.md`,
// scenario S-003.
//
// Building a message and carrying it are separate jobs, so nothing here sends
// anything: a message is built and handed back, and whoever owns the transport
// sends it. What this owns is the part that must not be got wrong twice — the
// order and the numbers the wrist will read.
//
// The order travels with the message instead of the rule travelling with it: the
// phone sorts by its own Foods I Eat rule (`foods_i_eat_order.dart`) before it
// sends, and the wrist shows what it was sent in the order it arrived. The wrist
// then does its own thing on top — what the user quick-logs moves to the front —
// which is why the two surfaces agree about where a food sits without either
// owning the other's list.

library;

import '../sync_protocol/phone_envelope.dart';
import '../sync_protocol/wire_timestamps.dart';
import 'food_helpers.dart';
import 'foods_i_eat_order.dart';
import '../../data/models/models.dart';

abstract final class WatchReferenceSync {
  /// The phone's foods, as the `foods_down` message the wrist reads.
  ///
  /// [generatedAt] is what makes a rebuild the same message rather than a newer
  /// one: a list nobody has added to since carries the timestamp it arrived
  /// with, and a wrist holding it drops the duplicate.
  static Map<String, Object?> buildFoodsDown({
    required List<Food> foods,
    required List<FoodGroup> groups,
    required DateTime generatedAt,
  }) {
    final ordered = [
      for (final section in foodsIEatSections(foods: foods, groups: groups))
        for (final food in section.foods) food,
    ];
    final categoryNames = {for (final group in groups) group.id: group.name};
    final categories = categoryNames.keys.toList()
      ..sort(
        (left, right) =>
            compareFoodNames(categoryNames[left]!, categoryNames[right]!),
      );

    return phoneEnvelope(
      type: 'foods_down',
      messageId: 'msg-foods-${generatedAt.toUtc().millisecondsSinceEpoch}',
      sentAt: generatedAt,
      payload: {
        'generatedAt': utcIso(generatedAt),
        'categories': [
          for (final id in categories)
            {'categoryId': id, 'name': categoryNames[id]!},
        ],
        'foods': [for (final food in ordered) _foodJson(food, categoryNames)],
      },
    );
  }

  /// One food, in the shape the schema pins. A food whose group the phone no
  /// longer holds has no category to name, which is a valid answer rather than
  /// a reason to drop the food.
  static Map<String, Object?> _foodJson(
    Food food,
    Map<String, String> categoryNames,
  ) {
    final groupId = food.groupId;
    final amount = food.lastAmountConsumed;
    return {
      'foodId': food.id,
      'name': food.name,
      'categoryId': groupId != null && categoryNames.containsKey(groupId)
          ? groupId
          : null,
      'referenceAmount': food.referenceAmount,
      'referenceLabel': food.referenceLabel,
      // One serving is one reference amount, so the energy per serving is the
      // energy of the macros on the food — the phone's own derivation, so the
      // wrist and the card cannot disagree about what a food costs.
      'caloriesPerServing': calculateCalories(food),
      // The portion the user last took, in servings. A food nobody has logged
      // offers one serving, which is the phone's own pre-fill rule.
      'defaultServings': amount == null || food.referenceAmount <= 0
          ? 1
          : amount / food.referenceAmount,
    };
  }
}
