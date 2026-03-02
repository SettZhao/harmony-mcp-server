/**
 * Interface for a single serial port.
 * Ported from usb-serial-for-android (Android) to HarmonyOS ArkTS
 *
 * Key differences:
 * - open() takes USBDevicePipe instead of UsbDeviceConnection
 * - All I/O operations are async (Promise-based) due to HarmonyOS USB API being async
 * - byte[] replaced with Uint8Array
 */
import { usbManager } from '@kit.BasicServicesKit';

export interface IUsbSerialDriver {
  getDevice(): usbManager.USBDevice;
  getPorts(): IUsbSerialPort[];
}

export interface IUsbSerialPort {
  getDriver(): IUsbSerialDriver;
  getPortNumber(): number;
  getSerial(): string;

  open(pipe: usbManager.USBDevicePipe): Promise<void>;
  close(): Promise<void>;

  read(dest: Uint8Array, timeoutMillis: number): Promise<number>;
  write(src: Uint8Array, timeoutMillis: number): Promise<number>;

  setParameters(baudRate: number, dataBits: number, stopBits: number, parity: number): Promise<void>;

  getCD(): boolean;
  getCTS(): boolean;
  getDSR(): boolean;
  getDTR(): boolean;
  setDTR(value: boolean): Promise<void>;
  getRI(): boolean;
  getRTS(): boolean;
  setRTS(value: boolean): Promise<void>;

  purgeHwBuffers(flushRX: boolean, flushTX: boolean): Promise<boolean>;
}
