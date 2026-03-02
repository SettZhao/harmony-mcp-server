/**
 * UsbSerialProber - Discovers USB serial devices and matches them to drivers
 * Ported from usb-serial-for-android UsbSerialProber to HarmonyOS ArkTS
 *
 * Key differences:
 * - Uses usbManager.getDevices() instead of Android UsbManager.getDeviceList()
 * - No permissions needed to enumerate devices; requestRight() needed before connecting
 * - Driver registration via ProbeTable with factory functions instead of Java reflection
 */
import { usbManager } from '@kit.BasicServicesKit';
import { IUsbSerialDriver } from './IUsbSerial';
import { ProbeTable } from './ProbeTable';
import { CdcAcmSerialDriver } from './CdcAcmSerialDriver';
import { FtdiSerialDriver } from './FtdiSerialDriver';
import { Cp21xxSerialDriver } from './Cp21xxSerialDriver';
import { Ch34xSerialDriver } from './Ch34xSerialDriver';
import { ProlificSerialDriver } from './ProlificSerialDriver';

/**
 * UsbSerialProber enumerates USB devices and finds matching serial drivers.
 *
 * Typical usage:
 *   const prober = UsbSerialProber.getDefaultProber();
 *   const drivers = prober.findAllDrivers();
 *   for each driver: await driver.getPorts()[0].open(pipe);
 */
export class UsbSerialProber {
  private mProbeTable: ProbeTable;

  constructor(probeTable: ProbeTable) {
    this.mProbeTable = probeTable;
  }

  /**
   * Build a ProbeTable pre-loaded with all built-in drivers.
   */
  static getDefaultProbeTable(): ProbeTable {
    const table: ProbeTable = new ProbeTable();

    table.addDriver(CdcAcmSerialDriver.getSupportedDevices(),
      (device: usbManager.USBDevice) => new CdcAcmSerialDriver(device));

    table.addDriver(FtdiSerialDriver.getSupportedDevices(),
      (device: usbManager.USBDevice) => new FtdiSerialDriver(device));

    table.addDriver(Cp21xxSerialDriver.getSupportedDevices(),
      (device: usbManager.USBDevice) => new Cp21xxSerialDriver(device));

    table.addDriver(Ch34xSerialDriver.getSupportedDevices(),
      (device: usbManager.USBDevice) => new Ch34xSerialDriver(device));

    table.addDriver(ProlificSerialDriver.getSupportedDevices(),
      (device: usbManager.USBDevice) => new ProlificSerialDriver(device));

    return table;
  }

  /**
   * Get the default prober backed by the built-in probe table.
   */
  static getDefaultProber(): UsbSerialProber {
    return new UsbSerialProber(UsbSerialProber.getDefaultProbeTable());
  }

  /**
   * Probe a single device, returning a driver if a match is found or null otherwise.
   */
  probeDevice(device: usbManager.USBDevice): IUsbSerialDriver | null {
    const vendorId = device.vendorId;
    const productId = device.productId;
    const factory = this.mProbeTable.findDriver(vendorId, productId);
    if (factory !== null) {
      return factory(device);
    }
    return null;
  }

  /**
   * Find all connected USB devices that match a registered driver.
   * Returns a list of driver instances (one per matching device).
   *
   * Note: Does NOT call requestRight(). Caller must request USB permission
   * before calling open() on any port.
   */
  findAllDrivers(): IUsbSerialDriver[] {
    const result: IUsbSerialDriver[] = [];
    const deviceList: usbManager.USBDevice[] = usbManager.getDevices();
    for (let i = 0; i < deviceList.length; i++) {
      const device = deviceList[i];
      const driver = this.probeDevice(device);
      if (driver !== null) {
        result.push(driver);
      }
    }
    return result;
  }
}
