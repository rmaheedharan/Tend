# Why Tend shows you at most three things

*Explanation · Requirements: UX-2, FR-B1 · Built in M1 (engine only; the Now screen arrives in M3)*

When you open a long list, you have to sort it before you can start. Sorting takes energy, and it is the energy you
were going to use on the task. Tend does that sorting for you and hands you **no more than three things**. That is
the Rule of Three.

## What "fits right now" means

Tend only offers a task when it makes sense at this moment. A task fits when all of these are true:

- **Its time has come.** It is inside the window you gave it, not before.
- **It is the right part of the day.** Tend splits the day into morning (5 am to noon), afternoon (noon to 5 pm),
  evening (5 pm to 10 pm) and night (10 pm to 5 am). Each task has the parts of the day and the days of the week that
  suit it. Night is quiet unless you say a task belongs there.
- **It matches your energy.** On a low-energy day you only see light tasks. On a normal day you see light and normal
  tasks. On a high-energy day you see everything.
- **The weather allows it.** A task that needs good weather, like washing the car, only shows up when it is clear or
  cloudy. If Tend does not know the weather, it leaves those tasks for another time rather than guess.
- **You have not asked for a rest from it.** If you set a task aside until a later date, Tend keeps it out of sight
  until then.

## How Tend picks the three

If more than three tasks fit, Tend picks in a fixed order:

1. Important things that came back for a second look (like a bill), first.
2. Then the tasks whose window closes soonest.
3. Then important tasks before everyday ones.

The same moment always gives the same three. Nothing is random.

If nothing fits right now, Tend shows nothing. That is a normal, restful result, not a problem.

## Why this is built into the engine

The limit of three is not a setting on one screen. It is part of the engine that every screen reads from: the Now
screen, widgets and the Live Activity all get the same answer of three or fewer. No screen can ask for a longer list,
because the engine has no way to give one.

## Related

- [Why nothing in Tend ever counts against you](compassionate-rescheduling.md)
- For builders: [TendCore architecture overview](../../architecture/overview.md), section "How UX-2 is enforced".
