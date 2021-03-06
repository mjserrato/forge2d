part of forge2d;

class EdgeAndCircleContact extends Contact {
  EdgeAndCircleContact(Fixture fA, int indexA, Fixture fB, int indexB)
      : super(fA, indexA, fB, indexB) {
    assert(_fixtureA.getType() == ShapeType.EDGE);
    assert(_fixtureB.getType() == ShapeType.CIRCLE);
  }

  @override
  void evaluate(Manifold manifold, Transform xfA, Transform xfB) {
    World.collision.collideEdgeAndCircle(
      manifold,
      _fixtureA.getShape() as EdgeShape,
      xfA,
      _fixtureB.getShape() as CircleShape,
      xfB,
    );
  }
}
