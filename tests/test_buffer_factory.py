import unittest
import numpy as np
from unittest.mock import Mock, call
import tracemalloc
import gc
import buffer_interface as bi  # Assuming this is your interface module

class Factory(bi.BufferFactory):
    def AllocateBuffer(self, size: int):
        print("Factory.AllocateBuffer")
        buffer = np.ones(size, dtype=np.uint8)
        return buffer

    def FreeBuffer(self, buffer_object):
        print("Factory.FreeBuffer")
        del(buffer_object)

    def OnBufferFactoryDeregistered(self):
        print("Factory.DestroyBufferFactory")


class FactoryException_OnBufferFactoryDeregistered(Factory):
    def OnBufferFactoryDeregistered(self):
        raise Exception("Error OnBufferFactoryDeregistered")

class FaFactoryException_AllocateBuffer(bi.BufferFactory):
    def AllocateBuffer(self, size: int):
        raise Exception("Error AllocateBuffer")

class FaFactoryException_FreeBuffer(bi.BufferFactory):
    def FreeBuffer(self, buffer_object):
        raise Exception("Error FreeBuffer")

class TestLeaks(unittest.TestCase):
    def test_set_buffer_factory(self):
        for _ in range(2):
            manager = bi.BufferManager()
            factory = FactoryException_OnBufferFactoryDeregistered()
            manager.SetBufferFactory(factory)
            manager.SetBufferFactory(factory)
            manager.SetBufferFactory(factory)
            manager.SetBufferFactory(factory)
            manager.SetBufferFactory(factory)

    def test_grabbing_and_get_buffer_object(self):
        print("test_grab")
        self.manager.SetBufferFactory(self.factory)  # Important!
        self.manager.StartGrabbing()

        for _ in range(2): # Test getting the object multiple times
            buffer_object = self.manager.GetBufferObject()
            self.assertIsInstance(buffer_object, np.ndarray) # Or whatever your buffer type is
            self.assertGreater(buffer_object.size, 0) # Check if buffer has some size
            self.assertEqual(buffer_object.dtype, np.uint8)

        self.manager.StopGrabbing()



class TestFactory(unittest.TestCase):
    def setUp(self):
        tracemalloc.start()
        self.factory = Factory()
        self.manager = bi.BufferManager()

    def tearDown(self):
        del self.manager
        del self.factory
        snapshot = tracemalloc.take_snapshot()
        top_stats = snapshot.statistics('lineno')
        for stat in top_stats[:10]: 
            print(stat)

        current, peak = tracemalloc.get_traced_memory()
        print(f"Current memory usage: {current / 10**6}MB; Peak: {peak / 10**6}MB")
        self.assertLess(current, 20 * 10**6, "Memory usage too high (adjust threshold)") # Example

        tracemalloc.stop()

    def test_allocate_buffer(self):
        size = 10
        buffer = self.factory.AllocateBuffer(size)
        self.assertIsInstance(buffer, np.ndarray)
        self.assertEqual(buffer.size, size)
        self.assertEqual(buffer.dtype, np.uint8)
        self.assertTrue(np.all(buffer == 1)) # Check if initialized with ones


class TestBufferManager(unittest.TestCase):

    def setUp(self):
       self.factory = Factory()
       self.manager = bi.BufferManager()

    def tearDown(self):
        print("cleanup")
        import gc
        gc.collect()

    def test_set_buffer_factory(self):
        self.manager.SetBufferFactory(self.factory)
        self.manager.SetBufferFactory(self.factory)
        self.manager.SetBufferFactory(self.factory)
        self.manager.SetBufferFactory(self.factory)
        self.manager.SetBufferFactory(self.factory)

    def test_grabbing_and_get_buffer_object(self):
        print("test_grab")
        self.manager.SetBufferFactory(self.factory)  # Important!
        self.manager.StartGrabbing()

        for _ in range(2): # Test getting the object multiple times
            buffer_object = self.manager.GetBufferObject()
            self.assertIsInstance(buffer_object, np.ndarray) # Or whatever your buffer type is
            self.assertGreater(buffer_object.size, 0) # Check if buffer has some size
            self.assertEqual(buffer_object.dtype, np.uint8)

        self.manager.StopGrabbing()

    
if __name__ == '__main__':
    unittest.main()



