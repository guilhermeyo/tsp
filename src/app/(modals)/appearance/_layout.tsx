import { Stack } from 'expo-router';

/**
 * A Stack INSIDE the sheet, so Font and Size can push.
 *
 * SwiftUI's default `Picker` style is a row showing the current value and a
 * chevron; tapping it pushes a list of the cases onto the enclosing
 * NavigationStack. Reproducing that needs a real navigator here — an action
 * sheet or a dropdown would be a different control with different mechanics
 * (no back button, no title, no swipe-back).
 */
export default function AppearanceLayout() {
  return (
    <>
      {/*
        No `name`, so this configures THIS route in the PARENT navigator: it
        turns off the header the (modals) stack would otherwise draw around the
        whole nested stack. Without it every screen in here wears two headers,
        because the inner stack draws its own.
      */}
      <Stack.Screen options={{ headerShown: false }} />
      {/*
        `card`, not `modal`: the parent group presents modally, but Font and
        Size must slide in from the side as pushes.
      */}
      <Stack screenOptions={{ presentation: 'card' }} />
    </>
  );
}
