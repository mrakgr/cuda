{-# LANGUAGE ForeignFunctionInterface #-}
--------------------------------------------------------------------------------
-- |
-- Module    : Foreign.CUDA.Marshal
-- Copyright : (c) 2009 Trevor L. McDonell
-- License   : BSD
--
-- Memory allocation and marshalling support for CUDA devices
--
--------------------------------------------------------------------------------

module Foreign.CUDA.Marshal
  (
    DevicePtr,

    -- ** Allocation
    malloc,
    malloc2D,
    memset,

    -- ** Marshalling

    -- ** Combined allocation and marshalling

    -- ** Copying
    memcpy,
    memcpyAsync,
  )
  where

import Foreign.CUDA.Error
import Foreign.CUDA.Stream
import Foreign.CUDA.Internal.C2HS hiding (malloc)

#include <cuda_runtime_api.h>
{# context lib="cudart" #}


--------------------------------------------------------------------------------
-- Data Types
--------------------------------------------------------------------------------

-- |
-- A reference to data stored on the device
--
newtype DevicePtr = DevicePtr (ForeignPtr ())

withDevicePtr               :: DevicePtr -> (Ptr () -> IO b) -> IO b
withDevicePtr (DevicePtr d) =  withForeignPtr d

newDevicePtr      :: FinalizerPtr () -> Ptr () -> IO DevicePtr
newDevicePtr fp p =  newForeignPtr fp p >>= (return.DevicePtr)

--
-- Memory copy
--
{# enum cudaMemcpyKind as CopyDirection {}
    with prefix="cudaMemcpy" deriving (Eq, Show) #}


--------------------------------------------------------------------------------
-- Allocation
--------------------------------------------------------------------------------

-- |
-- Allocate the specified number of bytes in linear memory on the device. The
-- memory is suitably aligned for any kind of variable, and is not cleared.
--
malloc       :: Integer -> IO (Either String DevicePtr)
malloc bytes = do
    (rv,ptr) <- cudaMalloc bytes
    case rv of
        Success -> doAutoRelease free_ >>= \fp ->
                   newDevicePtr fp ptr >>= (return.Right)
        _       -> return.Left $ describe rv

{# fun unsafe cudaMalloc
    { alloca-  `Ptr ()'  peek* ,
      cIntConv `Integer'       } -> `Status' cToEnum #}

-- |
-- Allocate at least @width * height@ bytes of linear memory on the device. The
-- function may pad the allocation to ensure corresponding pointers in each row
-- meet coalescing requirements. The actual allocation width is returned.
--
malloc2D :: Integer          -- ^ width in bytes
         -> Integer          -- ^ height in bytes
         -> IO (Either String (DevicePtr,Integer))
malloc2D width height =  do
    (rv,ptr,pitch) <- cudaMallocPitch width height
    case rv of
        Success -> doAutoRelease free_ >>= \fp ->
                   newDevicePtr fp ptr >>= \dp -> return.Right $ (dp,pitch)
        _       -> return.Left $ describe rv

{# fun unsafe cudaMallocPitch
    { alloca-  `Ptr ()'  peek*        ,
      alloca-  `Integer' peekIntConv* ,
      cIntConv `Integer'              ,
      cIntConv `Integer'              } -> `Status' cToEnum #}


-- |
-- Allocate at least @width * height * depth@ bytes of linear memory on the
-- device. The function may pad the allocation to ensure hardware alignment
-- requirements are met. The actual allocation width is returned
--


-- |
-- Free previously allocated memory on the device
--
-- free   :: Ptr () -> IO (Maybe String)
-- free p =  nothingIfOk `fmap` cudaFree p

free_   :: Ptr () -> IO ()
free_ p =  throwIf_ (/= Success) (describe) (cudaFree p)

{# fun unsafe cudaFree
    { id `Ptr ()' } -> `Status' cToEnum #}

foreign import ccall "wrapper"
    doAutoRelease   :: (Ptr () -> IO ()) -> IO (FunPtr (Ptr () -> IO ()))

-- |
-- Copy data between host and device
--
memcpy :: DevicePtr -> DevicePtr -> Integer -> CopyDirection -> IO (Maybe String)
memcpy dst src bytes dir =  nothingIfOk `fmap` cudaMemcpy dst src bytes dir

{# fun unsafe cudaMemcpy
    { withDevicePtr* `DevicePtr'     ,
      withDevicePtr* `DevicePtr'     ,
      cIntConv       `Integer'       ,
      cFromEnum      `CopyDirection' } -> `Status' cToEnum #}

-- |
-- Copy data between host and device asynchronously
--
memcpyAsync :: DevicePtr -> DevicePtr -> Integer -> CopyDirection -> Stream -> IO (Maybe String)
memcpyAsync dst src bytes dir stream =  nothingIfOk `fmap` cudaMemcpyAsync dst src bytes dir stream

{# fun unsafe cudaMemcpyAsync
    { withDevicePtr* `DevicePtr'     ,
      withDevicePtr* `DevicePtr'     ,
      cIntConv       `Integer'       ,
      cFromEnum      `CopyDirection' ,
      cIntConv       `Stream'        } -> `Status' cToEnum #}

-- |
-- Initialize device memory to a given value
--
memset                  :: DevicePtr -> Integer -> Int -> IO (Maybe String)
memset ptr bytes symbol =  nothingIfOk `fmap` cudaMemset ptr symbol bytes

{# fun unsafe cudaMemset
    { withDevicePtr* `DevicePtr' ,
                     `Int'       ,
      cIntConv       `Integer'   } -> `Status' cToEnum #}
