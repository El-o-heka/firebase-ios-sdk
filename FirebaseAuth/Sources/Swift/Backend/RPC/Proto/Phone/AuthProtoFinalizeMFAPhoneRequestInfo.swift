// Copyright 2023 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation

@objc(FIRAuthProtoFinalizeMFAPhoneRequestInfo)
public class AuthProtoFinalizeMFAPhoneRequestInfo: NSObject,
  AuthProto {
  public required init(dictionary: [String: AnyHashable]) {
    fatalError()
  }

  var sessionInfo: String?
  var code: String?
  @objc public init(sessionInfo: String?, verificationCode: String?) {
    self.sessionInfo = sessionInfo
    code = verificationCode
  }

  public var dictionary: [String: AnyHashable] {
    var dict: [String: AnyHashable] = [:]
    if let sessionInfo = sessionInfo {
      dict["sessionInfo"] = sessionInfo
    }
    if let code = code {
      dict["code"] = code
    }
    return dict
  }
}
