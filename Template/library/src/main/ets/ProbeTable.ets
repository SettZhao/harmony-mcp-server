/**
 * ProbeTable - Maps USB (vendorId, productId) pairs to driver factories
 * Ported from usb-serial-for-android ProbeTable to HarmonyOS ArkTS
 *
 * Key differences:
 * - Java reflection (Class<T>, Constructor.newInstance) replaced with typed factory functions
 * - Map key is string "vendorId:productId" since Map requires a hashable key
 */
import { usbManager } from '@kit.BasicServicesKit';
import { IUsbSerialDriver } from './IUsbSerial';

/**
 * Factory function type: given a USBDevice, creates a driver instance.
 */
export type DriverFactory = (device: usbManager.USBDevice) => IUsbSerialDriver;

/**
 * ProbeTable maintains a mapping of USB vendor/product IDs to driver factories.
 * Usage:
 *   const table = new ProbeTable();
 *   table.addProduct(VENDOR_FTDI, FTDI_FT232R, (dev) => new FtdiSerialDriver(dev));
 *   const factory = table.findDriver(vendorId, productId);
 *   if (factory) { const driver = factory(device); }
 */
export class ProbeTable {
  private mProbeTable: Map<string, DriverFactory> = new Map();

  /**
   * Add a specific USB product to the probe table.
   * Returns `this` for method chaining.
   */
  addProduct(vendorId: number, productId: number, factory: DriverFactory): ProbeTable {
    const key = vendorId.toString(16) + ':' + productId.toString(16);
    this.mProbeTable.set(key, factory);
    return this;
  }

  /**
   * Add all products from a driver's getSupportedDevices() map.
   * The supportedDevices map should be {vendorId -> [productId, ...]}
   */
  addDriver(supportedDevices: Map<number, number[]>, factory: (device: usbManager.USBDevice) => IUsbSerialDriver): ProbeTable {
    supportedDevices.forEach((productIds: number[], vendorId: number) => {
      for (let i = 0; i < productIds.length; i++) {
        this.addProduct(vendorId, productIds[i], factory);
      }
    });
    return this;
  }

  /**
   * Look up a driver factory by vendorId and productId.
   * Returns null if no matching driver is registered.
   */
  findDriver(vendorId: number, productId: number): DriverFactory | null {
    const key = vendorId.toString(16) + ':' + productId.toString(16);
    const factory = this.mProbeTable.get(key);
    return factory !== undefined ? factory : null;
  }

  /**
   * Returns the number of registered entries.
   */
  size(): number {
    return this.mProbeTable.size;
  }
}
