import { StyleSheet, TextInput } from 'react-native';
import type { TextInputProps } from 'react-native';

/**
 * One text row of a grouped form, sized like the `UITableViewCell` SwiftUI's
 * `Form` would have drawn around a bare `TextField`.
 *
 * Deliberately dumb: it holds no state, knows nothing about the launcher or the
 * store, and takes both of its colours as props rather than reading a context.
 * The original had no visible labels either -- the placeholder IS the label --
 * so there is nothing here to render above the input.
 */
export interface FormFieldProps
  extends Pick<
    TextInputProps,
    | 'value'
    | 'onChangeText'
    | 'placeholder'
    | 'autoCapitalize'
    | 'autoCorrect'
    | 'keyboardType'
    | 'keyboardAppearance'
    | 'returnKeyType'
    | 'onSubmitEditing'
    | 'autoFocus'
  > {
  /** Colour of the typed text. */
  color: string;
  /** Colour of the placeholder. */
  placeholderColor: string;
}

export function FormField({ color, placeholderColor, ...input }: FormFieldProps) {
  return (
    <TextInput {...input} placeholderTextColor={placeholderColor} style={[styles.field, { color }]} />
  );
}

const styles = StyleSheet.create({
  field: {
    // 44pt is the standard iOS row height and 17pt the body size a Form uses.
    height: 44,
    paddingHorizontal: 16,
    fontSize: 17,
  },
});
