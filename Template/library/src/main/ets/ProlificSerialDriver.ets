/**
 * Prolific PL2303 USB Serial Driver
 * Ported from usb-serial-for-android ProlificSerialDriver to HarmonyOS ArkTS
 */
import { usbManager } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { IUsbSerialDriver, IUsbSerialPort } from './IUsbSerial';
import { CommonUsbSerialPort } from './CommonUsbSerialPort';
import {
  PARITY_NONE, PARITY_ODD, PARITY_EVEN, PARITY_MARK, PARITY_SPACE,
  STOPBITS_1, STOPBITS_1_5, STOPBITS_2,
  DATABITS_5, DATABITS_6, DATABITS_7, DATABITS_8
} from './UsbSerialTypes';
import * as UsbId from './UsbId';

const TAG = 'ProlificSerialDriver';
const DOMAIN = 0x0000;

const USB_READ_TIMEOUT_MILLIS = 1000;
const USB_WRITE_TIMEOUT_MILLIS = 5000;

const USB_RECIP_INTERFACE = 0x01;
const PROLIFIC_VENDOR_READ_REQUEST = 0x01;
const PROLIFIC_VENDOR_WRITE_REQUEST = 0x01;

const PROLIFIC_VENDOR_OUT_REQTYPE = 0x40; // USB_DIR_OUT | USB_TYPE_VENDOR
const PROLIFIC_VENDOR_IN_REQTYPE = 0xC0;  // USB_DIR_IN | USB_TYPE_VENDOR
const PROLIFIC_CTRL_OUT_REQTYPE = 0x21;   // USB_DIR_OUT | USB_TYPE_CLASS | USB_RECIP_INTERFACE

const WRITE_ENDPOINT = 0x02;
const READ_ENDPOINT = 0x83;
const INTERRUPT_ENDPOINT = 0x81;

const FLUSH_RX_REQUEST = 0x08;
const FLUSH_TX_REQUEST = 0x09;

const SET_LINE_REQUEST = 0x20;
const SET_CONTROL_REQUEST = 0x22;

const CONTROL_DTR = 0x01;
const CONTROL_RTS = 0x02;

const STATUS_FLAG_CD = 0x01;
const STATUS_FLAG_DSR = 0x02;
const STATUS_FLAG_RI = 0x08;
const STATUS_FLAG_CTS = 0x80;

const STATUS_BUFFER_SIZE = 10;
const STATUS_BYTE_IDX = 8;

const DEVICE_TYPE_HX = 0;
const DEVICE_TYPE_0 = 1;
const DEVICE_TYPE_1 = 2;

class ProlificSerialPort extends CommonUsbSerialPort {
  private mDriverRef: ProlificSerialDriver;
  private mDeviceType: number = DEVICE_TYPE_HX;
  private mReadEndpoint: usbManager.USBEndpoint | null = null;
  private mWriteEndpoint: usbManager.USBEndpoint | null = null;
  private mInterruptEndpoint: usbManager.USBEndpoint | null = null;
  private mControlLinesValue: number = 0;
  private mBaudRate: number = -1;
  private mDataBits: number = -1;
  private mStopBits: number = -1;
  private mParity: number = -1;
  private mStatus: number = 0;

  constructor(device: usbManager.USBDevice, portNumber: number, driver: ProlificSerialDriver) {
    super(device, portNumber);
    this.mDriverRef = driver;
  }

  getDriver(): IUsbSerialDriver {
    return this.mDriverRef;
  }

  private async inControlTransfer(requestType: number, request: number, value: number, index: number, length: number): Promise<Uint8Array> {
    const buffer = new Uint8Array(length);
    const result = await this.controlTransfer(requestType, request, value, index, buffer, length, USB_READ_TIMEOUT_MILLIS);
    if (result !== length) {
      throw new Error('ControlTransfer with value 0x' + value.toString(16) + ' failed: ' + result);
    }
    return buffer;
  }

  private async outControlTransfer(requestType: number, request: number, value: number, index: number, data: Uint8Array | null): Promise<void> {
    const length = data ? data.length : 0;
    const result = await this.controlTransfer(requestType, request, value, index, data, length, USB_WRITE_TIMEOUT_MILLIS);
    if (result !== length) {
      throw new Error('ControlTransfer with value 0x' + value.toString(16) + ' failed: ' + result);
    }
  }

  private async vendorIn(value: number, index: number, length: number): Promise<Uint8Array> {
    return this.inControlTransfer(PROLIFIC_VENDOR_IN_REQTYPE, PROLIFIC_VENDOR_READ_REQUEST, value, index, length);
  }

  private async vendorOut(value: number, index: number, data: Uint8Array | null): Promise<void> {
    return this.outControlTransfer(PROLIFIC_VENDOR_OUT_REQTYPE, PROLIFIC_VENDOR_WRITE_REQUEST, value, index, data);
  }

  private async ctrlOut(request: number, value: number, index: number, data: Uint8Array | null): Promise<void> {
    return this.outControlTransfer(PROLIFIC_CTRL_OUT_REQTYPE, request, value, index, data);
  }

  private async doBlackMagic(): Promise<void> {
    await this.vendorIn(0x8484, 0, 1);
    await this.vendorOut(0x0404, 0, null);
    await this.vendorIn(0x8484, 0, 1);
    await this.vendorIn(0x8383, 0, 1);
    await this.vendorIn(0x8484, 0, 1);
    await this.vendorOut(0x0404, 1, null);
    await this.vendorIn(0x8484, 0, 1);
    await this.vendorIn(0x8383, 0, 1);
    await this.vendorOut(0, 1, null);
    await this.vendorOut(1, 0, null);
    await this.vendorOut(2, (this.mDeviceType === DEVICE_TYPE_HX) ? 0x44 : 0x24, null);
  }

  private async setControlLines(newControlLinesValue: number): Promise<void> {
    await this.ctrlOut(SET_CONTROL_REQUEST, newControlLinesValue, 0, null);
    this.mControlLinesValue = newControlLinesValue;
  }

  private async resetDevice(): Promise<void> {
    await this.purgeHwBuffers(true, true);
  }

  private async getStatus(): Promise<number> {
    const buffer = new Uint8Array(STATUS_BUFFER_SIZE);
    if (!this.mInterruptEndpoint) {
      return 0;
    }
    const readBytes = await this.bulkTransfer(this.mInterruptEndpoint, buffer, 100);
    if (readBytes === STATUS_BUFFER_SIZE) {
      this.mStatus = buffer[STATUS_BYTE_IDX] & 0xFF;
    }
    return this.mStatus;
  }

  async open(pipe: usbManager.USBDevicePipe): Promise<void> {
    if (this.mPipe !== null) {
      throw new Error('Already open');
    }

    const configs = this.mDevice.configs;
    if (!configs || configs.length === 0) {
      throw new Error('No USB configurations');
    }
    const usbInterface = configs[0].interfaces[0];

    if (usbManager.claimInterface(pipe, usbInterface, true) !== 0) {
      throw new Error('Error claiming Prolific interface 0');
    }

    this.mPipe = pipe;
    let opened = false;
    try {
      for (let i = 0; i < usbInterface.endpoints.length; i++) {
        const ep = usbInterface.endpoints[i];
        if (ep.address === READ_ENDPOINT) {
          this.mReadEndpoint = ep;
        } else if (ep.address === WRITE_ENDPOINT) {
          this.mWriteEndpoint = ep;
        } else if (ep.address === INTERRUPT_ENDPOINT) {
          this.mInterruptEndpoint = ep;
        }
      }

      // Detect device type via raw descriptor
      if (this.mDevice.clazz === 0x02) {
        this.mDeviceType = DEVICE_TYPE_0;
      } else {
        try {
          const rawDescriptors = usbManager.getRawDescriptor(pipe);
          if (rawDescriptors && rawDescriptors.length >= 8) {
            const maxPacketSize0 = rawDescriptors[7];
            if (maxPacketSize0 === 64) {
              this.mDeviceType = DEVICE_TYPE_HX;
            } else if (this.mDevice.clazz === 0x00 || this.mDevice.clazz === 0xFF) {
              this.mDeviceType = DEVICE_TYPE_1;
            } else {
              this.mDeviceType = DEVICE_TYPE_HX;
            }
          }
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'Could not detect PL2303 subtype, assuming HX: %{public}s', JSON.stringify(e));
          this.mDeviceType = DEVICE_TYPE_HX;
        }
      }

      await this.setControlLines(this.mControlLinesValue);
      await this.resetDevice();
      await this.doBlackMagic();
      opened = true;
    } finally {
      if (!opened) {
        this.mPipe = null;
        usbManager.releaseInterface(pipe, usbInterface);
      }
    }
  }

  async close(): Promise<void> {
    if (this.mPipe === null) {
      throw new Error('Already closed');
    }
    try {
      await this.resetDevice();
    } finally {
      const configs = this.mDevice.configs;
      if (configs && configs.length > 0) {
        usbManager.releaseInterface(this.mPipe, configs[0].interfaces[0]);
      }
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

  async setParameters(baudRate: number, dataBits: number, stopBits: number, parity: number): Promise<void> {
    if (this.mBaudRate === baudRate && this.mDataBits === dataBits &&
        this.mStopBits === stopBits && this.mParity === parity) {
      return;
    }

    const lineRequestData = new Uint8Array(7);
    lineRequestData[0] = baudRate & 0xFF;
    lineRequestData[1] = (baudRate >> 8) & 0xFF;
    lineRequestData[2] = (baudRate >> 16) & 0xFF;
    lineRequestData[3] = (baudRate >> 24) & 0xFF;

    if (stopBits === STOPBITS_1) {
      lineRequestData[4] = 0;
    } else if (stopBits === STOPBITS_1_5) {
      lineRequestData[4] = 1;
    } else if (stopBits === STOPBITS_2) {
      lineRequestData[4] = 2;
    } else {
      throw new Error('Unknown stopBits value: ' + stopBits);
    }

    if (parity === PARITY_NONE) {
      lineRequestData[5] = 0;
    } else if (parity === PARITY_ODD) {
      lineRequestData[5] = 1;
    } else if (parity === PARITY_EVEN) {
      lineRequestData[5] = 2;
    } else if (parity === PARITY_MARK) {
      lineRequestData[5] = 3;
    } else if (parity === PARITY_SPACE) {
      lineRequestData[5] = 4;
    } else {
      throw new Error('Unknown parity value: ' + parity);
    }

    lineRequestData[6] = dataBits & 0xFF;

    await this.ctrlOut(SET_LINE_REQUEST, 0, 0, lineRequestData);

    this.mBaudRate = baudRate;
    this.mDataBits = dataBits;
    this.mStopBits = stopBits;
    this.mParity = parity;
  }

  getCD(): boolean {
    return (this.mStatus & STATUS_FLAG_CD) !== 0;
  }

  getCTS(): boolean {
    return (this.mStatus & STATUS_FLAG_CTS) !== 0;
  }

  getDSR(): boolean {
    return (this.mStatus & STATUS_FLAG_DSR) !== 0;
  }

  getDTR(): boolean {
    return (this.mControlLinesValue & CONTROL_DTR) !== 0;
  }

  async setDTR(value: boolean): Promise<void> {
    let newVal = this.mControlLinesValue;
    if (value) {
      newVal |= CONTROL_DTR;
    } else {
      newVal &= ~CONTROL_DTR;
    }
    await this.setControlLines(newVal);
  }

  getRI(): boolean {
    return (this.mStatus & STATUS_FLAG_RI) !== 0;
  }

  getRTS(): boolean {
    return (this.mControlLinesValue & CONTROL_RTS) !== 0;
  }

  async setRTS(value: boolean): Promise<void> {
    let newVal = this.mControlLinesValue;
    if (value) {
      newVal |= CONTROL_RTS;
    } else {
      newVal &= ~CONTROL_RTS;
    }
    await this.setControlLines(newVal);
  }

  async purgeHwBuffers(purgeReadBuffers: boolean, purgeWriteBuffers: boolean): Promise<boolean> {
    if (purgeReadBuffers) {
      await this.vendorOut(FLUSH_RX_REQUEST, 0, null);
    }
    if (purgeWriteBuffers) {
      await this.vendorOut(FLUSH_TX_REQUEST, 0, null);
    }
    return purgeReadBuffers || purgeWriteBuffers;
  }
}

export class ProlificSerialDriver implements IUsbSerialDriver {
  private mDevice: usbManager.USBDevice;
  private mPort: IUsbSerialPort;

  constructor(device: usbManager.USBDevice) {
    this.mDevice = device;
    this.mPort = new ProlificSerialPort(device, 0, this);
  }

  getDevice(): usbManager.USBDevice {
    return this.mDevice;
  }

  getPorts(): IUsbSerialPort[] {
    return [this.mPort];
  }

  static getSupportedDevices(): Map<number, number[]> {
    const devices: Map<number, number[]> = new Map();
    devices.set(UsbId.VENDOR_PROLIFIC, [UsbId.PROLIFIC_PL2303]);
    return devices;
  }
}
