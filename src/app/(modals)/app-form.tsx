import * as Linking from 'expo-linking';
import { Stack, useLocalSearchParams, useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

// The catalog owns the hand-back channel and documents it in its own header.
// It is a module-scope single-listener slot rather than a router return param,
// because a param would survive the back-navigation and re-fire on remount --
// re-clobbering the fields every time this screen came back into view.
import { catalogSelection } from './catalog';

import { FormField } from '@/components/FormField';
import { useLauncherStore, useTheme } from '@/store/LauncherStore';

/**
 * SCREEN 2 -- the unified add/edit form. ONE view, two modes, exactly as
 * `AppFormView` was: the mode changes the two initial field values, the title,
 * the confirm label and whether the Delete section exists. Nothing else.
 */
export default function AppFormScreen() {
  const router = useRouter();
  const store = useLauncherStore();
  const theme = useTheme();
  const colors = palette(theme.isDark);

  // The declared return type is `Record<string, string | string[]>`, which lies:
  // in add mode there is no `id` at all. Hence the typeof check rather than a
  // generic parameter -- Expo Router's own param type has no `undefined` in it.
  const params = useLocalSearchParams();
  const editingID = typeof params.id === 'string' ? params.id : null;
  const isEditing = editingID !== null;

  // Seeded ONCE, from the store as it was at mount. This form deliberately does
  // not observe the store, mirroring the value snapshot the Swift sheet captured
  // in `init`. If the app is edited or deleted from elsewhere while this sheet
  // is open, the form still saves its own stale-plus-edits copy, and
  // `store.update` silently no-ops when the id has vanished -- the sheet
  // dismisses either way, exactly as before.
  const [snapshot] = useState(() =>
    editingID === null ? null : (store.config.apps.find((app) => app.id === editingID) ?? null)
  );
  const [name, setName] = useState(() => snapshot?.name ?? '');
  const [urlString, setUrlString] = useState(() => snapshot?.urlString ?? '');

  useEffect(
    () =>
      catalogSelection.subscribe((entry) => {
        // Overwrites BOTH fields unconditionally, clobbering anything typed, in
        // add and edit mode alike. It prefills and nothing more: no store call,
        // no persistence. The user still has to tap Add or Save.
        setName(entry.name);
        setUrlString(entry.urlString);
      }),
    []
  );

  // JavaScript's `trim` strips the same set as Swift's `.whitespacesAndNewlines`.
  const trimmedName = name.trim();
  const trimmedURL = urlString.trim();

  // The entire validation surface of this app. No URL syntax check, no scheme
  // allowlist, no duplicate detection, no length limit, no existence check.
  // A name of "x" and a URL of "x" is valid; whitespace-only is not.
  const canSave = trimmedName !== '' && trimmedURL !== '';

  function dismiss() {
    router.back();
  }

  function save() {
    if (editingID !== null) {
      // Same id, so `update` replaces in place and LIST POSITION IS PRESERVED.
      // List order is the widget's render order; a remove-then-append here would
      // silently reshuffle the user's widget on every typo fix.
      store.update({ id: editingID, name: trimmedName, urlString: trimmedURL });
    } else {
      // The raw, UNTRIMMED strings, matching the original asymmetry: the edit
      // path trims here, the add path lets the store trim. Behaviour is
      // identical only for as long as `addCustom` keeps trimming -- if that ever
      // went away, added apps would keep their leading/trailing whitespace while
      // edited ones would not.
      store.addCustom(name, urlString);
    }
    dismiss();
  }

  return (
    <>
      <Stack.Screen
        options={{
          title: isEditing ? 'Edit App' : 'Add App',
          headerLeft: () => (
            // Discards every local edit with no unsaved-changes prompt. Swipe-down
            // does the same, which is why interactive dismissal is left enabled.
            <Pressable onPress={dismiss} hitSlop={8}>
              <Text style={[styles.headerButton, { color: colors.tint }]}>Cancel</Text>
            </Pressable>
          ),
          headerRight: () => (
            <Pressable onPress={save} disabled={!canSave} hitSlop={8}>
              <Text
                style={[
                  styles.headerButton,
                  styles.headerConfirm,
                  { color: canSave ? colors.tint : colors.disabled },
                ]}
              >
                {isEditing ? 'Save' : 'Add'}
              </Text>
            </Pressable>
          ),
        }}
      />

      <ScrollView
        style={[styles.screen, { backgroundColor: colors.groupedBackground }]}
        contentContainerStyle={styles.content}
        keyboardShouldPersistTaps="handled"
        // Reproduces the keyboard avoidance a SwiftUI Form gets for free. Native
        // contentInset adjustment, so no KeyboardAvoidingView wrapper is needed.
        automaticallyAdjustKeyboardInsets
      >
        <View style={[styles.section, { backgroundColor: colors.sectionBackground }]}>
          <FormField
            value={name}
            onChangeText={setName}
            placeholder="Name"
            autoCapitalize="sentences"
            autoCorrect
            color={colors.label}
            placeholderColor={colors.placeholder}
            // The Dark toggle used to re-skin the keyboard too, via
            // `.preferredColorScheme` on the WindowGroup. React Native has no
            // window-level override, so every input says it explicitly.
            keyboardAppearance={theme.isDark ? 'dark' : 'light'}
          />
          <View style={[styles.separator, { backgroundColor: colors.separator }]} />
          <FormField
            value={urlString}
            onChangeText={setUrlString}
            // Unicode ellipsis, not three periods. This string is user-visible
            // and was copied verbatim from the original.
            placeholder="URL (spotify:// or https://…)"
            autoCapitalize="none"
            autoCorrect={false}
            keyboardType="url"
            color={colors.label}
            placeholderColor={colors.placeholder}
            keyboardAppearance={theme.isDark ? 'dark' : 'light'}
          />
        </View>

        <View style={[styles.section, { backgroundColor: colors.sectionBackground }]}>
          <Pressable
            style={({ pressed }) => [styles.row, pressed && { backgroundColor: colors.pressed }]}
            onPress={() => router.push('/(modals)/catalog')}
          >
            <Text style={[styles.rowLabel, { color: colors.tint }]}>Choose from catalog</Text>
          </Pressable>
          <View style={[styles.separator, { backgroundColor: colors.separator }]} />
          {/*
            Tapping a row in the LIST opens this form, so before this button the
            only way to find out whether a URL actually worked was to put the
            widget on a home screen and tap it there. That is a terrible loop for
            the one thing about this app that is genuinely trial and error: a URL
            scheme names a protocol, not an app, so whether a given string opens
            the app you meant is an empirical question about THIS phone.
          */}
          <Pressable
            style={({ pressed }) => [styles.row, pressed && { backgroundColor: colors.pressed }]}
            disabled={urlString.trim().length === 0}
            onPress={() => {
              const target = urlString.trim();
              Linking.openURL(target).catch(() => {
                Alert.alert(
                  'Could not open this',
                  `iOS refused to open:\n\n${target}\n\n` +
                    'No installed app handles it. If the app IS installed, its scheme ' +
                    'changed, or another app claimed the same one.'
                );
              });
            }}
          >
            <Text
              style={[
                styles.rowLabel,
                { color: urlString.trim().length === 0 ? colors.disabled : colors.tint },
              ]}
            >
              Test this URL
            </Text>
          </Pressable>
        </View>

        {editingID !== null && (
          <View style={[styles.section, { backgroundColor: colors.sectionBackground }]}>
            <Pressable
              style={({ pressed }) => [styles.row, pressed && { backgroundColor: colors.pressed }]}
              onPress={() => {
                // No confirmation, no action sheet, no undo. The second of two
                // independent delete paths, both unconfirmed in the original.
                store.removeById(editingID);
                dismiss();
              }}
            >
              <Text style={[styles.rowLabel, { color: colors.destructive }]}>Delete</Text>
            </Pressable>
          </View>
        )}
      </ScrollView>
    </>
  );
}

interface Palette {
  groupedBackground: string;
  sectionBackground: string;
  separator: string;
  label: string;
  placeholder: string;
  tint: string;
  disabled: string;
  destructive: string;
  pressed: string;
}

/**
 * The grouped-form chrome, which in SwiftUI came free from `Form` reacting to
 * the window's colour scheme. React Native exposes no system colour catalogue,
 * so the handful of UIKit values an inset-grouped form actually uses are spelled
 * out here and driven by `theme.isDark` -- the same flag the Dark toggle writes,
 * so this sheet flips with the rest of the app.
 *
 * Note this is the FORM's chrome, not the launcher's: `theme.backgroundColor`
 * is never painted here. In the original only the widget preview card used it.
 */
function palette(isDark: boolean): Palette {
  return isDark
    ? {
        groupedBackground: '#000000',
        sectionBackground: '#1C1C1E',
        separator: '#38383A',
        label: '#FFFFFF',
        placeholder: 'rgba(235, 235, 245, 0.3)',
        tint: '#0A84FF',
        disabled: 'rgba(235, 235, 245, 0.3)',
        destructive: '#FF453A',
        pressed: '#2C2C2E',
      }
    : {
        groupedBackground: '#F2F2F7',
        sectionBackground: '#FFFFFF',
        separator: '#C6C6C8',
        label: '#000000',
        placeholder: 'rgba(60, 60, 67, 0.3)',
        tint: '#007AFF',
        disabled: 'rgba(60, 60, 67, 0.3)',
        destructive: '#FF3B30',
        pressed: '#D1D1D6',
      };
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
  },
  content: {
    paddingTop: 20,
    paddingBottom: 32,
    // iOS inset-grouped section spacing.
    gap: 35,
  },
  section: {
    marginHorizontal: 16,
    borderRadius: 10,
    overflow: 'hidden',
  },
  separator: {
    height: StyleSheet.hairlineWidth,
    // Inset to the row's text, the way a table view insets its separators.
    marginLeft: 16,
  },
  row: {
    height: 44,
    paddingHorizontal: 16,
    justifyContent: 'center',
  },
  rowLabel: {
    fontSize: 17,
  },
  headerButton: {
    fontSize: 17,
  },
  headerConfirm: {
    // `.confirmationAction` renders semibold; `.cancellationAction` does not.
    fontWeight: '600',
  },
});
