/**
 * USB Serial Constants - data bits, stop bits, parity, flow control
 * Ported from usb-serial-for-android (Android) to HarmonyOS ArkTS
 */

// Data bits
export const DATABITS_5: number = 5;
export const DATABITS_6: number = 6;
export const DATABITS_7: number = 7;
export const DATABITS_8: number = 8;

// Flow control
export const FLOWCONTROL_NONE: number = 0;
export const FLOWCONTROL_RTSCTS_IN: number = 1;
export const FLOWCONTROL_RTSCTS_OUT: number = 2;
export const FLOWCONTROL_XONXOFF_IN: number = 4;
export const FLOWCONTROL_XONXOFF_OUT: number = 8;

// Parity
export const PARITY_NONE: number = 0;
export const PARITY_ODD: number = 1;
export const PARITY_EVEN: number = 2;
export const PARITY_MARK: number = 3;
export const PARITY_SPACE: number = 4;

// Stop bits
export const STOPBITS_1: number = 1;
export const STOPBITS_1_5: number = 3;
export const STOPBITS_2: number = 2;
