import 'package:flutter_test/flutter_test.dart';
import 'package:retro_collec/catalog.dart';
import 'package:retro_collec/trades.dart';

void main() {
  const card = RcCard(
    id: 'test',
    sys: 'test',
    num: 1,
    title: 'Test',
    year: null,
    dev: '',
    pub: '',
    genre: '',
    rarity: 3,
    img: '',
    shot: null,
    desc: '',
  );

  setUp(() => Catalog.cards = {card.id: card});
  tearDown(() => Catalog.cards = {});

  test('calcule les valeurs selon la finition et chaque exemplaire', () {
    expect(tradeValue([]), 0);
    expect(tradeValue([('test', 0), ('test', 1), ('test', 1), ('test', 3)]), 2220);
    expect(tradeValue([('test', 2)]), 600);
  });

  test('ignore une carte absente du catalogue comme le détail existant', () {
    expect(tradeValue([('inconnue', 0), ('test', 0)]), 60);
  });
}
