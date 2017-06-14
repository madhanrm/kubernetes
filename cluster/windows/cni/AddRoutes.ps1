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


$endpointName = "cbr0"
$vnicName = "vEthernet ($endpointName)"

function
Add-RouteToPodCIDR()
{
    '''
    $route = get-netroute -InterfaceAlias "$vnicName" -DestinationPrefix $clusterCIDR -erroraction Ignore
    if (!$route) 
    {
        New-Netroute -DestinationPrefix $clusterCIDR -InterfaceAlias "$vnicName" -NextHop 0.0.0.0 -Verbose
    }

    '''
    $podCIDRs=c:\k\kubectl.exe  --kubeconfig=c:\k\config get nodes -o=custom-columns=Name:.status.nodeInfo.operatingSystem,PODCidr:.spec.podCIDR --no-headers
    Write-Host "Add-RouteToPodCIDR - available nodes $podCIDRs"
    foreach ($podcidr in $podCIDRs)
    {
        $tmp = $podcidr.Split(" ")
        $os = $tmp | select -First 1
        $cidr = $tmp | select -Last 1
        $cidrGw =  $cidr.substring(0,$cidr.lastIndexOf(".")) + ".1"

        
        if ($os -eq "windows") {
            $cidrGw = $cidr.substring(0,$cidr.lastIndexOf(".")) + ".2"
        }

        Write-Host "Adding route for Remote Pod CIDR $cidr, GW $cidrGw, for node type $os"

        $route = get-netroute -InterfaceAlias "$vnicName" -DestinationPrefix $cidr -erroraction Ignore
        if (!$route) {
            new-netroute -InterfaceAlias "$vnicName" -DestinationPrefix $cidr -NextHop  $cidrGw -Verbose
        }
    }
}

Add-RouteToPodCIDR
