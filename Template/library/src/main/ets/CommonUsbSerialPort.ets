/**
 * Abstract base class for USB serial port implementations.
 * Ported from usb-serial-for-android Android CommonUsbSerialPort to HarmonyOS ArkTS
 *
 * Key changes:
 * - UsbDeviceConnection replaced by USBDevicePipe (stored after open())
 * - bulkTransfer() and controlTransfer() are async (await-ed)
 * - byte[] replaced with Uint8Array
 * - synchronized blocks removed (ArkTS is single-threaded)
 * - System.arraycopy() replaced with Uint8Array.set()
 */
import { usbManager } from '@kit.BasicServicesKit';
import { IUsbSerialPort, IUsbSerialDriver } from './IUsbSerial';

export const DEFAULT_READ_BUFFER_SIZE: number = 16 * 1024;
export const DEFAULT_WRITE_BUFFER_SIZE: number = 16 * 1024;

export abstract class CommonUsbSerialPort implements IUsbSerialPort {
  protected mDevice: usbManager.USBDevice;
  protected mPortNumber: number;
  protected mPipe: usbManager.USBDevicePipe | null = null;

  protected mReadBuffer: Uint8Array;
  protected mWriteBuffer: Uint8Array;

  constructor(device: usbManager.USBDevice, portNumber: number) {
    this.mDevice = device;
    this.mPortNumber = portNumber;
    this.mReadBuffer = new Uint8Array(DEFAULT_READ_BUFFER_SIZE);
    this.mWriteBuffer = new Uint8Array(DEFAULT_WRITE_BUFFER_SIZE);
  }

  getDevice(): usbManager.USBDevice {
    return this.mDevice;
  }

  getPortNumber(): number {
    return this.mPortNumber;
  }

  getSerial(): string {
    return this.mDevice.serial ?? '';
  }

  setReadBufferSize(bufferSize: number): void {
    if (bufferSize !== this.mReadBuffer.length) {
      this.mReadBuffer = new Uint8Array(bufferSize);
    }
  }

  setWriteBufferSize(bufferSize: number): void {
    if (bufferSize !== this.mWriteBuffer.length) {
      this.mWriteBuffer = new Uint8Array(bufferSize);
    }
  }

  abstract getDriver(): IUsbSerialDriver;
  abstract open(pipe: usbManager.USBDevicePipe): Promise<void>;
  abstract close(): Promise<void>;
  abstract read(dest: Uint8Array, timeoutMillis: number): Promise<number>;
  abstract write(src: Uint8Array, timeoutMillis: number): Promise<number>;
  abstract setParameters(baudRate: number, dataBits: number, stopBits: number, parity: number): Promise<void>;
  abstract getCD(): boolean;
  abstract getCTS(): boolean;
  abstract getDSR(): boolean;
  abstract getDTR(): boolean;
  abstract setDTR(value: boolean): Promise<void>;
  abstract getRI(): boolean;
  abstract getRTS(): boolean;
  abstract setRTS(value: boolean): Promise<void>;

  async purgeHwBuffers(flushRX: boolean, flushTX: boolean): Promise<boolean> {
    return !flushRX && !flushTX;
  }

  /**
   * Helper: bulkTransfer via HarmonyOS usbManager
   */
  protected async bulkTransfer(
    endpoint: usbManager.USBEndpoint,
    buffer: Uint8Array,
    timeoutMillis: number
  ): Promise<number> {
    if (!this.mPipe) {
      throw new Error('Port not open');
    }
    return usbManager.bulkTransfer(this.mPipe, endpoint, buffer, timeoutMillis);
  }

  /**
   * Helper: controlTransfer via HarmonyOS usbManager.usbControlTransfer
   * Maps Android controlTransfer(requestType, request, value, index, buffer, length, timeout)
   */
  protected async controlTransfer(
    requestType: number,
    request: number,
    value: number,
    index: number,
    buffer: Uint8Array | null,
    length: number,
    timeoutMillis: number
  ): Promise<number> {
    if (!this.mPipe) {
      throw new Error('Port not open');
    }
    const data = buffer ? buffer.subarray(0, length) : new Uint8Array(0);
    const params: usbManager.USBDeviceRequestParams = {
      bmRequestType: requestType,
      bRequest: request,
      wValue: value,
      wIndex: index,
      wLength: length,
      data: data
    };
    return usbManager.usbControlTransfer(this.mPipe, params, timeoutMillis);
  }
}
