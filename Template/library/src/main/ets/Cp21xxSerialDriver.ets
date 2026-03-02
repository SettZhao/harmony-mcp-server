/**
 * Silicon Labs CP21xx USB Serial Driver
 * Ported from usb-serial-for-android Cp21xxSerialDriver to HarmonyOS ArkTS
 */
import { usbManager } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { IUsbSerialDriver, IUsbSerialPort } from './IUsbSerial';
import { CommonUsbSerialPort } from './CommonUsbSerialPort';
import {
  DATABITS_5, DATABITS_6, DATABITS_7, DATABITS_8,
  PARITY_ODD, PARITY_EVEN,
  STOPBITS_1, STOPBITS_2
} from './UsbSerialTypes';
import * as UsbId from './UsbId';

const TAG = 'Cp21xxSerialDriver';
const DOMAIN = 0x0000;

const DEFAULT_BAUD_RATE = 9600;
const USB_WRITE_TIMEOUT_MILLIS = 5000;

// Request types
const REQTYPE_HOST_TO_DEVICE = 0x41;

// Request codes
const SILABSER_IFC_ENABLE_REQUEST_CODE = 0x00;
const SILABSER_SET_BAUDDIV_REQUEST_CODE = 0x01;
const SILABSER_SET_LINE_CTL_REQUEST_CODE = 0x03;
const SILABSER_SET_MHS_REQUEST_CODE = 0x07;
const SILABSER_SET_BAUDRATE = 0x1E;
const SILABSER_FLUSH_REQUEST_CODE = 0x12;

const FLUSH_READ_CODE = 0x0a;
const FLUSH_WRITE_CODE = 0x05;

const UART_ENABLE = 0x0001;
const UART_DISABLE = 0x0000;

const BAUD_RATE_GEN_FREQ = 0x384000;

const MCR_DTR = 0x0001;
const MCR_RTS = 0x0002;
const MCR_ALL = 0x0003;
const CONTROL_WRITE_DTR = 0x0100;
const CONTROL_WRITE_RTS = 0x0200;

class Cp21xxSerialPort extends CommonUsbSerialPort {
  private mDriverRef: Cp21xxSerialDriver;
  private mReadEndpoint: usbManager.USBEndpoint | null = null;
  private mWriteEndpoint: usbManager.USBEndpoint | null = null;

  constructor(device: usbManager.USBDevice, portNumber: number, driver: Cp21xxSerialDriver) {
    super(device, portNumber);
    this.mDriverRef = driver;
  }

  getDriver(): IUsbSerialDriver {
    return this.mDriverRef;
  }

  private async setConfigSingle(request: number, value: number): Promise<number> {
    return this.controlTransfer(REQTYPE_HOST_TO_DEVICE, request, value, 0, null, 0, USB_WRITE_TIMEOUT_MILLIS);
  }

  async open(pipe: usbManager.USBDevicePipe): Promise<void> {
    if (this.mPipe !== null) {
      throw new Error('Already opened.');
    }
    this.mPipe = pipe;
    let opened = false;
    try {
      const configs = this.mDevice.configs;
      if (!configs || configs.length === 0) {
        throw new Error('No USB configurations found');
      }
      const interfaces = configs[0].interfaces;
      for (let i = 0; i < interfaces.length; i++) {
        const res = usbManager.claimInterface(this.mPipe, interfaces[i], true);
        hilog.info(DOMAIN, TAG, 'claimInterface %{public}d result=%{public}d', i, res);
      }

      const dataIface = interfaces[interfaces.length - 1];
      for (let i = 0; i < dataIface.endpoints.length; i++) {
        const ep = dataIface.endpoints[i];
        if (ep.type === 2) { // USB_ENDPOINT_XFER_BULK
          if (ep.direction === 0x80) {
            this.mReadEndpoint = ep;
          } else {
            this.mWriteEndpoint = ep;
          }
        }
      }

      await this.setConfigSingle(SILABSER_IFC_ENABLE_REQUEST_CODE, UART_ENABLE);
      await this.setConfigSingle(SILABSER_SET_MHS_REQUEST_CODE, MCR_ALL | CONTROL_WRITE_DTR | CONTROL_WRITE_RTS);
      await this.setConfigSingle(SILABSER_SET_BAUDDIV_REQUEST_CODE, Math.floor(BAUD_RATE_GEN_FREQ / DEFAULT_BAUD_RATE));
      opened = true;
    } finally {
      if (!opened) {
        await this.close();
      }
    }
  }

  async close(): Promise<void> {
    if (this.mPipe === null) {
      throw new Error('Already closed');
    }
    try {
      await this.setConfigSingle(SILABSER_IFC_ENABLE_REQUEST_CODE, UART_DISABLE);
      usbManager.closePipe(this.mPipe);
    } finally {
      this.mPipe = null;
    }
  }

  async read(dest: Uint8Array, timeoutMillis: number): Promise<number> {
    if (!this.mReadEndpoint) {
      throw new Error('Read endpoint not set');
    }
    const readAmt = Math.min(dest.length, this.mReadBuffer.length);
    const readBuf = this.mReadBuffer.subarray(0, readAmt);
    const numBytesRead = await this.bulkTransfer(this.mReadEndpoint, readBuf, timeoutMillis);
    if (numBytesRead < 0) {
      return 0;
    }
    dest.set(this.mReadBuffer.subarray(0, numBytesRead), 0);
    return numBytesRead;
  }

  async write(src: Uint8Array, timeoutMillis: number): Promise<number> {
    if (!this.mWriteEndpoint) {
      throw new Error('Write endpoint not set');
    }
    let offset = 0;
    while (offset < src.length) {
      const writeLength = Math.min(src.length - offset, this.mWriteBuffer.length);
      const writeBuffer = offset === 0 ? src.subarray(0, writeLength) : (() => {
        this.mWriteBuffer.set(src.subarray(offset, offset + writeLength), 0);
        return this.mWriteBuffer.subarray(0, writeLength);
      })();
      const amtWritten = await this.bulkTransfer(this.mWriteEndpoint, writeBuffer, timeoutMillis);
      if (amtWritten <= 0) {
        throw new Error('Error writing ' + writeLength + ' bytes at offset ' + offset);
      }
      offset += amtWritten;
    }
    return offset;
  }

  private async setBaudRate(baudRate: number): Promise<void> {
    const data = new Uint8Array(4);
    data[0] = baudRate & 0xFF;
    data[1] = (baudRate >> 8) & 0xFF;
    data[2] = (baudRate >> 16) & 0xFF;
    data[3] = (baudRate >> 24) & 0xFF;
    const ret = await this.controlTransfer(REQTYPE_HOST_TO_DEVICE, SILABSER_SET_BAUDRATE, 0, 0, data, 4, USB_WRITE_TIMEOUT_MILLIS);
    if (ret < 0) {
      throw new Error('Error setting baud rate.');
    }
  }

  async setParameters(baudRate: number, dataBits: number, stopBits: number, parity: number): Promise<void> {
    await this.setBaudRate(baudRate);

    let configDataBits = 0;
    if (dataBits === DATABITS_5) {
      configDataBits |= 0x0500;
    } else if (dataBits === DATABITS_6) {
      configDataBits |= 0x0600;
    } else if (dataBits === DATABITS_7) {
      configDataBits |= 0x0700;
    } else {
      configDataBits |= 0x0800;
    }

    if (parity === PARITY_ODD) {
      configDataBits |= 0x0010;
    } else if (parity === PARITY_EVEN) {
      configDataBits |= 0x0020;
    }

    if (stopBits === STOPBITS_2) {
      configDataBits |= 2;
    }

    await this.setConfigSingle(SILABSER_SET_LINE_CTL_REQUEST_CODE, configDataBits);
  }

  getCD(): boolean { return false; }
  getCTS(): boolean { return false; }
  getDSR(): boolean { return false; }
  getDTR(): boolean { return true; }
  async setDTR(value: boolean): Promise<void> { }
  getRI(): boolean { return false; }
  getRTS(): boolean { return true; }
  async setRTS(value: boolean): Promise<void> { }

  async purgeHwBuffers(purgeReadBuffers: boolean, purgeWriteBuffers: boolean): Promise<boolean> {
    const value = (purgeReadBuffers ? FLUSH_READ_CODE : 0) | (purgeWriteBuffers ? FLUSH_WRITE_CODE : 0);
    if (value !== 0) {
      await this.setConfigSingle(SILABSER_FLUSH_REQUEST_CODE, value);
    }
    return true;
  }
}

export class Cp21xxSerialDriver implements IUsbSerialDriver {
  private mDevice: usbManager.USBDevice;
  private mPort: IUsbSerialPort;

  constructor(device: usbManager.USBDevice) {
    this.mDevice = device;
    this.mPort = new Cp21xxSerialPort(device, 0, this);
  }

  getDevice(): usbManager.USBDevice {
    return this.mDevice;
  }

  getPorts(): IUsbSerialPort[] {
    return [this.mPort];
  }

  static getSupportedDevices(): Map<number, number[]> {
    const devices: Map<number, number[]> = new Map();
    devices.set(UsbId.VENDOR_SILABS, [
      UsbId.SILABS_CP2102,
      UsbId.SILABS_CP2105,
      UsbId.SILABS_CP2108,
      UsbId.SILABS_CP2110
    ]);
    return devices;
  }
}
