# Copyright 2016 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.



#$env:INTERFACE_TO_ADD_SERVICE_IP="vEthernet (forwarder)"
#c:\k\kube-proxy.exe --v=4 --proxy-mode=usermode --hostname-override=15992acs9000 --kubeconfig=c:\k\config

$env:KUBE_NETWORK="l2bridge"
c:\k\kube-proxy.exe --v=4 --proxy-mode=kernelspace --hostname-override=$(hostname) --kubeconfig=c:\k\config
