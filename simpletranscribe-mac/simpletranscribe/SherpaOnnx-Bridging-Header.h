//
//  SherpaOnnx-Bridging-Header.h
//  simpletranscribe
//
//  Bridging header for sherpa-onnx C API.
//
//  SETUP: In Xcode Build Settings, set
//    "Objective-C Bridging Header" to:
//    simpletranscribe/SherpaOnnx-Bridging-Header.h
//

#ifndef SHERPA_ONNX_BRIDGING_HEADER_H
#define SHERPA_ONNX_BRIDGING_HEADER_H

#if __has_include("sherpa-onnx/c-api/c-api.h")
#import "sherpa-onnx/c-api/c-api.h"
#endif

#endif /* SHERPA_ONNX_BRIDGING_HEADER_H */
