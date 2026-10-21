import 'package:apps_examples/widgets/day_tile.dart';
import 'package:apps_examples/widgets/habit_row.dart';
import 'package:apps_examples/widgets/reorderable_column.dart';
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/habit_list.restage.g.dart';

/// Whether each row shows its name.
const bool _showNames = true;

/// One host-owned row value.
final class Habit {
  /// Creates an immutable row value.
  const Habit({required this.id, required this.name});

  /// Stable event identity.
  final String id;

  /// Current visible label.
  final String name;
}

/// A compact habit list served as a surface.
@Screen(id: 'habit_list', surface: Surface.general)
final class HabitList extends StatelessWidget {
  /// Creates the fallback screen.
  const HabitList({required this.habits, super.key});

  /// Current host-owned rows.
  final List<Habit> habits;

  /// A cell was tapped. Carries the row's id and the day's index.
  static const toggleDay = SurfaceEvent<String>('toggle_day');

  /// A row was dragged to a new position. Carries `[from, to]`.
  static const reorderRows = SurfaceEvent<List<int>>('reorder');

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'This week',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 18),
                  // The weekday header, aligned with each row's cells.
                  Row(
                    children: [
                      const Spacer(),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 6,
                        children: [
                          SizedBox(
                            width: 20,
                            child: Text(
                              'M',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 20,
                            child: Text(
                              'T',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 20,
                            child: Text(
                              'W',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 20,
                            child: Text(
                              'T',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 20,
                            child: Text(
                              'F',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 20,
                            child: Text(
                              'S',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 20,
                            child: Text(
                              'S',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ReorderableColumn(
                    onReorder: surfaceEvent(reorderRows),
                    children: [
                      for (final habit in habits)
                        HabitRow(
                          leading: const SizedBox(
                            width: 28,
                            child: Icon(
                              Icons.water_drop_rounded,
                              size: 22,
                              color: Color(0xFF37B6FF),
                            ),
                          ),
                          name: habit.name,
                          nameVisible: _showNames,
                          days: [
                            DayTile(
                              color: const Color(0xFF37B6FF),
                              onTap: surfaceEvent(toggleDay, habit.id),
                            ),
                            DayTile(
                              color: const Color(0xFF37B6FF),
                              onTap: surfaceEvent(toggleDay, habit.id),
                            ),
                            DayTile(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              onTap: surfaceEvent(toggleDay, habit.id),
                            ),
                            DayTile(
                              color: const Color(0xFF37B6FF),
                              onTap: surfaceEvent(toggleDay, habit.id),
                            ),
                            DayTile(
                              color: const Color(0xFF37B6FF),
                              onTap: surfaceEvent(toggleDay, habit.id),
                            ),
                            DayTile(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              onTap: surfaceEvent(toggleDay, habit.id),
                            ),
                            DayTile(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              onTap: surfaceEvent(toggleDay, habit.id),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
