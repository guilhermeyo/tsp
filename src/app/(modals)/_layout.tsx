import { Stack } from 'expo-router';

/**
 * Every editing surface in the app is a sheet, matching the Swift original
 * where the list presented `.sheet` for the form and for Appearance, and the
 * form presented a further `.sheet` for the catalog.
 *
 * The root layout is what makes this group arrive modally (see the note there:
 * react-native-screens renders the first screen of any stack as a push
 * controller, so a nested navigator cannot present its own root as a sheet).
 * `presentation: 'modal'` here governs the SECOND screen onward -- concretely,
 * the catalog rising over the form rather than sliding in from the side.
 *
 * Each route ships its own header, which is why the root layout hides the outer
 * one: in SwiftUI each sheet contained its own NavigationStack.
 */
export default function ModalsLayout() {
  return <Stack screenOptions={{ presentation: 'modal' }} />;
}
