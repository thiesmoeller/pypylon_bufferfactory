# test.py
import buffer_interface as bi
import gc


# adjust lifetime of factory when given to stream channel
bf = bi.Factory()
gc.collect()
m = bi.BufferManager()
gc.collect()
print(bf.AllocateBuffer(10))

m.SetBufferFactory(bf)
gc.collect()
m.StartGrabbing()
gc.collect()

m.StopGrabbing()
gc.collect()

print("finish")



