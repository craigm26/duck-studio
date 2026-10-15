"""Duck Cards, read by the duck: a code in a picture becomes a card, cards become rows, rows become
the plan Studio already runs. See ../README.md."""

from .cards import Deck, Seen, place
from .layout import arrange
from .program import Program, Step, check_plan, plan, read

__all__ = ["Deck", "Seen", "place", "arrange", "read", "plan", "check_plan", "Program", "Step"]
