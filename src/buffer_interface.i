%module(directors = "1") buffer_interface
%include "stdint.i"

%{
    #include <Python.h>
    #include <string>
    #include <cstdio>
    #include <stdexcept>
    #include <unordered_map>
    #include <mutex>
    #include <memory>

    // Helper function to build the full error message.
    std::string make_error_message(const char *base_message)
    {
        std::string err_msg(base_message);
        return err_msg;
    }

    // Custom deleter for PyObject* using Py_DECREF
    struct PyObjectDeleter
    {
        void operator()(PyObject* obj) const
        {
            Py_XDECREF(obj); // Use Py_XDECREF in case obj is nullptr
        }
    };

    // Type alias for convenience
    using PyObjectAutoPtr = std::unique_ptr<PyObject, PyObjectDeleter>;
%}

typedef unsigned int size_t;

// Enable directors
%feature("director") Pylon::IBufferFactory;

//
// Custom director typemap for AllocateBuffer.
//
// Original signature in C++:
//   virtual void AllocateBuffer( size_t bufferSize, void** pCreatedBuffer, intptr_t& bufferContext ) = 0;
//
// Our goal: have the Python override implement:
//
//     def AllocateBuffer(self, bufferSize):
//         # create a buffer (any object supporting the buffer protocol)
//         return buffer
//
// In this typemap, we call the Python override, expect a single object (not a tuple),
// then use its buffer protocol to extract the pointer and store its pointer for later release.
//
%typemap(directorin, noblock = 1)(size_t bufferSize, void **pCreatedBuffer, intptr_t &bufferContext)
{
    // in typemap: call the Python override with the buffer size.
    obj0 = PyLong_FromSsize_t($1);
    printf("C++: AllocateBuffer %ld\n", bufferSize);
}

%typemap(directorargout, noblock = 1)(size_t bufferSize, void **pCreatedBuffer, intptr_t &bufferContext)
{
    // Expect that the Python override returns a single object that supports the numpy protocol.
    PyObject *py_mem_obj = $result;
    if (!py_mem_obj)
    {
        std::string err_msg = make_error_message("No object returned from AllocateBuffer override");
        Swig::DirectorMethodException::raise(err_msg.c_str());
    }

    // **Limited API "NumPy array-like" check: Check for __array_interface__ attribute**
    PyObjectAutoPtr interface_dict(PyObject_GetAttrString(py_mem_obj, "__array_interface__"));
    if (interface_dict == NULL)
    {
       std::string err_msg = make_error_message("Object does not seem to implement __array_interface__");
       Swig::DirectorMethodException::raise(err_msg.c_str());
    }
    if (!PyDict_Check(interface_dict.get()))
    {
       std::string err_msg = make_error_message("__array_interface__ attribute is not a dictionary");
       Swig::DirectorMethodException::raise(err_msg.c_str());
    }

    // Get 'data' from the interface dictionary (Limited API dictionary access)
    auto data_value = PyDict_GetItemString(interface_dict.get(), "data");
    if (data_value == NULL)
    {
        std::string err_msg = make_error_message("'data' key not found in __array_interface__");
        Swig::DirectorMethodException::raise(err_msg.c_str());
    }

    if (!PyTuple_Check(data_value) || PyTuple_Size(data_value) != 2)
    {
       std::string err_msg = make_error_message("'data' in __array_interface__ is not a tuple of size 2");
       Swig::DirectorMethodException::raise(err_msg.c_str());
    }

    PyObject *address_obj = PyTuple_GetItem(data_value, 0); // Get the address from the tuple
    if (!PyLong_Check(address_obj))
    {
       std::string err_msg = make_error_message("Address in 'data' tuple is not an integer");
       Swig::DirectorMethodException::raise(err_msg.c_str());
    }
    auto data_ptr_int = PyLong_AsUnsignedLongLong(address_obj);

    // Get 'shape' from the interface dictionary (Limited API dictionary access)
    auto shape_value = PyDict_GetItemString(interface_dict.get(), "shape");
    if (shape_value == NULL)
    {
       std::string err_msg = make_error_message("'shape' key not found in __array_interface__");
       Swig::DirectorMethodException::raise(err_msg.c_str());
    }

    if (!PyTuple_Check(shape_value))
    {
       std::string err_msg = make_error_message("'shape' in __array_interface__ is not a tuple");
       Swig::DirectorMethodException::raise(err_msg.c_str());
    }

    // Increase the reference count so that the Python object stays alive,
    // then store its pointer (as intptr_t) for later use in FreeBuffer.
    // and GetBufferObject
    Py_INCREF(py_mem_obj);


    // Set the C++ pointer to point to the buffer's memory.
    *$2 = reinterpret_cast<void*>(data_ptr_int);
    // put the allocated memory object as pylon buffercontext
    $3 = reinterpret_cast<intptr_t>(py_mem_obj);
}

//
// Custom director typemap for FreeBuffer.
//
// Original signature in C++:
//   virtual void FreeBuffer(void* pCreatedBuffer, intptr_t bufferContext) = 0;
//
// Our goal: have the Python override implement:
//
//     def FreeBuffer(self, context):
//         # 'context' is the Python object whose lifetime was extended in AllocateBuffer
//         return
//
%typemap(directorin, noblock = 1)(void *pCreatedBuffer, intptr_t bufferContext)
{
    // in typemap
    PyObject *py_context = reinterpret_cast<PyObject *>($2);
    if (!py_context)
    {
        std::string err_msg = make_error_message("bufferContext is NULL; expected a valid PyObject pointer");
        Swig::DirectorMethodException::raise(err_msg.c_str());
    }

    obj0 = py_context;
    // give out a fresh reference to free alloc code
    Py_INCREF(obj0);
}

%typemap(directorargout, noblock = 1)(void *pCreatedBuffer, intptr_t bufferContext)
{
    // free the reference for the call
    Py_XDECREF(obj0);
    // free the result
    Py_XDECREF($result);
}

%typemap(directorin) void Pylon::IBufferFactory::DestroyBufferFactory
{
    // directorin typemap

}

// Rename the C++ method GetBufferContext to GetBufferObject in Python.
%rename(GetBufferObject) Pylon::BufferManager::GetBufferContext;

%typemap(in, numinputs=0, noblock=1) intptr_t &out_bufferContext (intptr_t temp)
{
    temp = 0; // Default value
    $1 = &temp;
}

// Custom out typemap for the out parameter (intptr_t &)
// that converts the stored pointer (which should be a PyObject*)
// into the corresponding Python object.
// If the pointer is NULL or not a valid Python object,
// raise a RuntimeError.
%typemap(argout)intptr_t &out_bufferContext
{
    //------------
    // Reinterpret the integer as a PyObject pointer.
    PyObject *py_obj = reinterpret_cast<PyObject *>(*$1);
    if (!py_obj)
    {
        SWIG_exception_fail(SWIG_RuntimeError, "GetBufferObject: stored pointer is NULL; not a valid PyObject");
    }

    if (!PyObject_TypeCheck(py_obj, &PyBaseObject_Type))
    {
        SWIG_exception_fail(SWIG_RuntimeError, "GetBufferObject: stored pointer is not a valid Python object");
    }

    // Increase the reference count to return a new reference.
    Py_INCREF(py_obj);
    $result = py_obj;
}

%ignore Pylon::BufferManager::SetBufferFactory;
%rename(SetBufferFactory) Pylon::BufferManager::_SetBufferFactory;
%extend Pylon::BufferManager {
    void _SetBufferFactory(Pylon::IBufferFactory *pFactory)
    {
        // we force to use Cleanup_Delete to get the DestroyBufferFactory Callback
        // that allows us to decrement the refcount of the factory
        self->SetBufferFactory(pFactory, Pylon::Cleanup_Delete);
    }
}


// Reference counting typemap for our wrapped version
%typemap(in) Pylon::IBufferFactory *pFactory {
    if ($input == Py_None)
    {
        $1 = nullptr;
    } else
    {
        void *argp = 0;
        int res = SWIG_ConvertPtr($input, &argp, $descriptor(Pylon::IBufferFactory *), 0);
        if (!SWIG_IsOK(res))
        {
            SWIG_exception_fail(SWIG_ArgError(res), "Expected IBufferFactory or None");
        }
        $1 = reinterpret_cast<Pylon::IBufferFactory *>(argp);
    }
}

%rename (BufferFactory) Pylon::IBufferFactory;
%rename (BufferManager) Pylon::BufferManager;

%rename(OnBufferFactoryDeregistered) Pylon::IBufferFactory::DestroyBufferFactory;


// Inline C++ code for the Pylon namespace
%inline%{

    namespace Pylon
    {
        class IBufferFactory
        {
        public:
            virtual ~IBufferFactory() = 0;

            virtual void AllocateBuffer(size_t bufferSize, void **pCreatedBuffer, intptr_t &bufferContext) = 0;

            virtual void FreeBuffer(void *pCreatedBuffer, intptr_t bufferContext) = 0;

            virtual void DestroyBufferFactory() = 0;
        };

        inline IBufferFactory::~IBufferFactory()
        {

        }

        enum ECleanup
        {
            Cleanup_None,
            Cleanup_Delete
        };

        class BufferManager
        {
        public:
            BufferManager() : m_factory(nullptr) {};
            virtual ~BufferManager()
            {
                printf("+++++~BufferManager\n");
                if (m_factory)
                {
                    m_factory->DestroyBufferFactory();
                    m_factory = nullptr;
                }
                printf("------~BufferManager\n");
            }
            virtual void SetBufferFactory(IBufferFactory *pFactory, ECleanup cleanupProcedure = Cleanup_Delete)
            {
                if (!pFactory)
                {
                    throw std::runtime_error("BufferFactory is invalid");
                }
                m_factory = pFactory;
            }

            virtual void StartGrabbing()
            {
                const size_t payloadsize = 1024 * 1024;
                m_factory->AllocateBuffer(payloadsize, &p_buffer, bufferContext);

                // demo fill image
                auto image_data = reinterpret_cast<uint8_t*>(p_buffer);
                for(size_t idx = 0; idx < payloadsize; idx++)
                {
                    image_data[idx] = static_cast<uint8_t>(idx%256);
                }
            }

            virtual void StopGrabbing()
            {
                m_factory->FreeBuffer(p_buffer, bufferContext);
                m_factory->DestroyBufferFactory();
                m_factory = nullptr;
            }

            virtual void GetBufferContext(intptr_t &out_bufferContext)
            {
                auto obj = reinterpret_cast<PyObject *>(this->bufferContext);
                out_bufferContext = this->bufferContext;
            }

        private:
            Pylon::IBufferFactory *m_factory;
            intptr_t bufferContext;
            void *p_buffer;
        };
    }
%}

%pythoncode %{
    class Factory(BufferFactory):
        def AllocateBuffer(self, size: int):
            print("Factory.AllocateBuffer")
            print(f"      Python: Allocating buffer of size {size}")
            buffer = np.ones(size, dtype=np.uint8)
            print(buffer.__array_interface__)
            print("allocate", buffer[:])
            return buffer

        def FreeBuffer(self, buffer_object):
            print("Factory.FreeBuffer")
            print("       Python: FreeBuffer called with buffer_object:", buffer_object, buffer_object.__array_interface__)
            del(buffer_object)

        def OnBufferFactoryDeregistered(self):
            print("Factory.DestroyBufferFactory")
            print("      Python: DestroyBufferFactory called")
            del self

    if __name__ == "__main__":
        import sys, gc
        import numpy as np
        print("This module is being run directly")
        bi = sys.modules[__name__]

        for _ in range(10000):
            bf = bi.Factory()
            m = bi.BufferManager()
            print("set buffer factory")
            m.SetBufferFactory(bf)
            gc.collect()

            print("start grabbing")
            m.StartGrabbing()
            print("get buffer object")
            for get_buf in range(10):
                a = m.GetBufferObject()
                print("this is python result:", a.__array_interface__)
                print("get_buffer", a[:])

            print("stop grabbing")
            m.StopGrabbing()
            del(bf)
            del(m)
            gc.collect()

        print("finish")
%}
