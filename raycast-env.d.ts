/// <reference types="@raycast/api">

/* 🚧 🚧 🚧
 * This file is auto-generated from the extension's manifest.
 * Do not modify manually. Instead, update the `package.json` file.
 * 🚧 🚧 🚧 */

/* eslint-disable @typescript-eslint/ban-types */

type ExtensionPreferences = {
  /** Play Sound Effects Through Current Output - Play system sounds through current output. */
  "systemOutput": boolean
}

/** Preferences accessible in all the extension's commands */
declare type Preferences = ExtensionPreferences

declare namespace Preferences {
  /** Preferences accessible in the `auto-switch-input` command */
  export type AutoSwitchInput = ExtensionPreferences & {}
  /** Preferences accessible in the `auto-switch-output` command */
  export type AutoSwitchOutput = ExtensionPreferences & {}
  /** Preferences accessible in the `customize-order` command */
  export type CustomizeOrder = ExtensionPreferences & {}
}

declare namespace Arguments {
  /** Arguments passed to the `auto-switch-input` command */
  export type AutoSwitchInput = {}
  /** Arguments passed to the `auto-switch-output` command */
  export type AutoSwitchOutput = {}
  /** Arguments passed to the `customize-order` command */
  export type CustomizeOrder = {}
}

