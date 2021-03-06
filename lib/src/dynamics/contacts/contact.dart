part of forge2d;

/// The class manages contact between two shapes. A contact exists for each overlapping AABB in the
/// broad-phase (except if filtered). Therefore a contact object may exist that has no contact
/// points.
/// TODO.spydon: Add generics
abstract class Contact {
  // Flags stored in _flags
  // Used when crawling contact graph when forming islands.
  static const int ISLAND_FLAG = 0x0001;
  // Set when the shapes are touching.
  static const int TOUCHING_FLAG = 0x0002;
  // This contact can be disabled (by user)
  static const int ENABLED_FLAG = 0x0004;
  // This contact needs filtering because a fixture filter was changed.
  static const int FILTER_FLAG = 0x0008;
  // This bullet contact had a TOI event
  static const int BULLET_HIT_FLAG = 0x0010;

  static const int TOI_FLAG = 0x0020;

  int flags = 0;

  // World pool and list pointers.
  Contact _prev;
  Contact _next;

  // Nodes for connecting bodies.
  final ContactEdge _nodeA = ContactEdge();
  final ContactEdge _nodeB = ContactEdge();

  final Fixture _fixtureA;
  final Fixture _fixtureB;

  final int _indexA;
  final int _indexB;

  final Manifold _manifold = Manifold();

  int toiCount = 0;
  double toi = 0.0;

  double _friction = 0.0;
  double _restitution = 0.0;

  double tangentSpeed = 0.0;

  Contact(this._fixtureA, this._indexA, this._fixtureB, this._indexB) {
    flags = ENABLED_FLAG;
    _manifold.pointCount = 0;
    _friction = Contact.mixFriction(
      _fixtureA._friction,
      _fixtureB._friction,
    );
    _restitution = Contact.mixRestitution(
      _fixtureA._restitution,
      _fixtureB._restitution,
    );
  }

  static Contact init(Fixture fA, int indexA, Fixture fB, int indexB) {
    // Remember that we use the order in the enum here to determine in which
    // order the arguments should come in the different contact classes.
    // { CIRCLE, EDGE, POLYGON, CHAIN }
    /// TODO.spydon: Clean this mess up.
    final ShapeType typeA =
        fA.getType().index < fB.getType().index ? fA.getType() : fB.getType();
    final ShapeType typeB = fA.getType() == typeA ? fB.getType() : fA.getType();
    final int indexTemp = indexA;
    indexA = fA.getType() == typeA ? indexA : indexB;
    indexB = fB.getType() == typeB ? indexB : indexTemp;
    final Fixture temp = fA;
    fA = fA.getType() == typeA ? fA : fB;
    fB = fB.getType() == typeB ? fB : temp;

    if (typeA == ShapeType.CIRCLE && typeB == ShapeType.CIRCLE) {
      return CircleContact(fA, fB);
    } else if (typeA == ShapeType.POLYGON && typeB == ShapeType.POLYGON) {
      return PolygonContact(fA, fB);
    } else if (typeA == ShapeType.CIRCLE && typeB == ShapeType.POLYGON) {
      return PolygonAndCircleContact(fB, fA);
    } else if (typeA == ShapeType.CIRCLE && typeB == ShapeType.EDGE) {
      return EdgeAndCircleContact(fB, indexB, fA, indexA);
    } else if (typeA == ShapeType.EDGE && typeB == ShapeType.POLYGON) {
      return EdgeAndPolygonContact(fA, indexA, fB, indexB);
    } else if (typeA == ShapeType.CIRCLE && typeB == ShapeType.CHAIN) {
      return ChainAndCircleContact(fB, indexB, fA, indexA);
    } else if (typeA == ShapeType.POLYGON && typeB == ShapeType.CHAIN) {
      return ChainAndPolygonContact(fB, indexB, fA, indexA);
    } else {
      assert(false, "Not compatible contact type");
      return CircleContact(fA, fB);
    }
  }

  /// Get the world manifold.
  void getWorldManifold(WorldManifold worldManifold) {
    final Body bodyA = _fixtureA.getBody();
    final Body bodyB = _fixtureB.getBody();
    final Shape shapeA = _fixtureA.getShape();
    final Shape shapeB = _fixtureB.getShape();

    worldManifold.initialize(_manifold, bodyA._transform, shapeA.radius,
        bodyB._transform, shapeB.radius);
  }

  /// Is this contact touching
  bool isTouching() {
    return (flags & TOUCHING_FLAG) == TOUCHING_FLAG;
  }

  /// Enable/disable this contact. This can be used inside the pre-solve contact listener. The
  /// contact is only disabled for the current time step (or sub-step in continuous collisions).
  void setEnabled(bool flag) {
    if (flag) {
      flags |= ENABLED_FLAG;
    } else {
      flags &= ~ENABLED_FLAG;
    }
  }

  /// Has this contact been disabled?
  bool isEnabled() {
    return (flags & ENABLED_FLAG) == ENABLED_FLAG;
  }

  /// Get the next contact in the world's contact list.
  Contact getNext() {
    return _next;
  }

  /// Get the first fixture in this contact.
  Fixture get fixtureA => _fixtureA;

  int getChildIndexA() {
    return _indexA;
  }

  /// Get the second fixture in this contact.
  Fixture get fixtureB => _fixtureB;

  int getChildIndexB() {
    return _indexB;
  }

  void resetFriction() {
    _friction = Contact.mixFriction(_fixtureA._friction, _fixtureB._friction);
  }

  void resetRestitution() {
    _restitution =
        Contact.mixRestitution(_fixtureA._restitution, _fixtureB._restitution);
  }

  void evaluate(Manifold manifold, Transform xfA, Transform xfB);

  /// Flag this contact for filtering. Filtering will occur the next time step.
  void flagForFiltering() {
    flags |= FILTER_FLAG;
  }

  // djm pooling
  final Manifold _oldManifold = Manifold();

  void update(ContactListener listener) {
    _oldManifold.set(_manifold);

    // Re-enable this contact.
    flags |= ENABLED_FLAG;

    bool touching = false;
    final bool wasTouching = (flags & TOUCHING_FLAG) == TOUCHING_FLAG;

    final bool sensorA = _fixtureA.isSensor();
    final bool sensorB = _fixtureB.isSensor();
    final bool sensor = sensorA || sensorB;

    final Body bodyA = _fixtureA.getBody();
    final Body bodyB = _fixtureB.getBody();
    final Transform xfA = bodyA._transform;
    final Transform xfB = bodyB._transform;

    if (sensor) {
      final Shape shapeA = _fixtureA.getShape();
      final Shape shapeB = _fixtureB.getShape();
      touching = World.collision
          .testOverlap(shapeA, _indexA, shapeB, _indexB, xfA, xfB);

      // Sensors don't generate manifolds.
      _manifold.pointCount = 0;
    } else {
      evaluate(_manifold, xfA, xfB);
      touching = _manifold.pointCount > 0;

      // Match old contact ids to new contact ids and copy the
      // stored impulses to warm start the solver.
      for (int i = 0; i < _manifold.pointCount; ++i) {
        final ManifoldPoint mp2 = _manifold.points[i];
        mp2.normalImpulse = 0.0;
        mp2.tangentImpulse = 0.0;
        final ContactID id2 = mp2.id;

        for (int j = 0; j < _oldManifold.pointCount; ++j) {
          final ManifoldPoint mp1 = _oldManifold.points[j];

          if (mp1.id.isEqual(id2)) {
            mp2.normalImpulse = mp1.normalImpulse;
            mp2.tangentImpulse = mp1.tangentImpulse;
            break;
          }
        }
      }

      if (touching != wasTouching) {
        bodyA.setAwake(true);
        bodyB.setAwake(true);
      }
    }

    if (touching) {
      flags |= TOUCHING_FLAG;
    } else {
      flags &= ~TOUCHING_FLAG;
    }

    if (listener == null) {
      return;
    }

    if (wasTouching == false && touching == true) {
      listener.beginContact(this);
    }

    if (wasTouching == true && touching == false) {
      listener.endContact(this);
    }

    if (sensor == false && touching) {
      listener.preSolve(this, _oldManifold);
    }
  }

  /// Friction mixing law. The idea is to allow either fixture to drive the restitution to zero. For
  /// example, anything slides on ice.
  static double mixFriction(double friction1, double friction2) {
    return math.sqrt(friction1 * friction2);
  }

  /// Restitution mixing law. The idea is allow for anything to bounce off an inelastic surface. For
  /// example, a super ball bounces on anything.
  static double mixRestitution(double restitution1, double restitution2) {
    return restitution1 > restitution2 ? restitution1 : restitution2;
  }
}
