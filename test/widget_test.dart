import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:seven_roses/tienda_app.dart';

void main() {
  testWidgets('admin app requires demo phone login', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TiendaApp());
    await tester.enterText(find.byType(TextField).first, '+50255550123');
    await tester.enterText(find.byType(TextField).last, 'wrong');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pump();
    expect(find.text('Número o contraseña incorrectos.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'SevenRoses2026!');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();
    expect(find.text('Buenos días, Mariana ☀️'), findsOneWidget);

    await tester.tap(find.text('Ventas'));
    await tester.pumpAndSettle();
    expect(find.text('Aún no hay compras.'), findsOneWidget);
    expect(find.text('Registrar venta'), findsNothing);
  });

  testWidgets('storefront checkout generates an automatic order',
      (tester) async {
    await mockNetworkImagesFor(() async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const TiendaApp(previewStorefront: true));
      await tester.pump();
      expect(find.text('SEVENROSES'), findsOneWidget);

      final addButton = find.byTooltip('Agregar a la bolsa').first;
      await tester.scrollUntilVisible(
        addButton,
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(addButton);
      await tester.pump();
      await tester.ensureVisible(find.byTooltip('Bolsa de compra'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Bolsa de compra'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Cliente de prueba');
      await tester.pump();
      await tester.tap(find.text('Confirmar compra'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Compra confirmada. Código: #SR-'),
          findsOneWidget);

      await tester.tap(find.text('¿Te ayudo?'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byType(TextField).last, '¿Tienen blazer de lino?');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();
      expect(find.textContaining('Blazer de lino está disponible'),
          findsOneWidget);
    });
  });
}
