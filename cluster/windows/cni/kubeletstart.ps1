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


# Todo : Get these values using kubectl
$KubeDnsServiceIp="11.0.0.10"

$clusterCIDR="192.168.0.0/16"
$serviceCIDR="11.0.0.0/8"

$WorkingDir = "c:\k"
$CNIPath = [Io.path]::Combine($WorkingDir , "cni")
$NetworkMode = "L2Bridge"
$CNIConfig = [Io.path]::Combine($CNIPath, "config", "$NetworkMode.conf")

$endpointName = "cbr0"
$vnicName = "vEthernet ($endpointName)"

function
Get-PodGateway($podCIDR)
{
    # Current limitation of Platform to not use .1 ip, since it is reserved
    return $podCIDR.substring(0,$podCIDR.lastIndexOf(".")) + ".1"
}

function
Get-PodEndpointGateway($podCIDR)
{
    # Current limitation of Platform to not use .1 ip, since it is reserved
    return $podCIDR.substring(0,$podCIDR.lastIndexOf(".")) + ".2"
}

function
Get-PodCIDR()
{
    $podCIDR=c:\k\kubectl.exe --kubeconfig=c:\k\config get nodes/$($(hostname).ToLower()) -o custom-columns=podCidr:.spec.podCIDR --no-headers
    return $podCIDR
}

function
Update-CNIConfig($podCIDR)
{
    $jsonSampleConfig = '{
  "cniVersion": "0.2.0",
  "name": "<NetworkMode>",
  "type": "wincni.exe",
  "master": "Ethernet",
  "ipam": {
     "environment": "azure",
     "subnet":"<PODCIDR>",
     "routes": [{
        "GW":"<PODGW>"
     }]
  },
  "dns" : {
    "Nameservers" : [ "11.0.0.10" ]
  },
  "AdditionalArgs" : [
    {
      "Name" : "EndpointPolicy", "Value" : { "Type" : "OutBoundNAT", "ExceptionList": [ "<ClusterCIDR>", "<ServerCIDR>" ] } 
    },
    {
      "Name" : "EndpointPolicy", "Value" : { "Type" : "ROUTE", "DestinationPrefix": "<ServerCIDR>", "NeedEncap" : true } 
    }
  ]
}'
    #Add-Content -Path $CNIConfig -Value $jsonSampleConfig

    $configJson =  ConvertFrom-Json $jsonSampleConfig 
    $configJson.name = $NetworkMode.ToLower()
    $configJson.ipam.subnet=$podCIDR
    $configJson.ipam.routes[0].GW = Get-PodEndpointGateway $podCIDR
    $configJson.dns.Nameservers[0] = $KubeDnsServiceIp

    $configJson.AdditionalArgs[0].Value.ExceptionList[0] = $clusterCIDR
    $configJson.AdditionalArgs[0].Value.ExceptionList[1] = $serviceCIDR

    $configJson.AdditionalArgs[1].Value.DestinationPrefix  = $serviceCIDR

    Clear-Content -Path $CNIConfig
    Add-Content -Path $CNIConfig -Value (ConvertTo-Json $configJson -Depth 20)
}

function
Test-PodCIDR($podCIDR)
{
    return $podCIDR.length -gt 0
}

try
{
    $podCIDR=Get-PodCIDR
    $podCidrDiscovered=Test-PodCIDR($podCIDR)

    # if the podCIDR has not yet been assigned to this node, start the kubelet process to get the podCIDR, and then promptly kill it.
    if (-not $podCidrDiscovered)
    {
        $argList = @("--hostname-override=$(hostname)","--pod-infra-container-image=kubletwin/pause","--resolv-conf=""""", "--kubeconfig=c:\k\config")

        $process = Start-Process -FilePath c:\k\kubelet.exe -PassThru -ArgumentList $argList

        # run kubelet until podCidr is discovered
        Write-Host "waiting to discover pod CIDR"
        while (-not $podCidrDiscovered)
        {
            Write-Host "Sleeping for 10s, and then waiting to discover pod CIDR"
            Start-Sleep -sec 10
            
            $podCIDR=Get-PodCIDR
            $podCidrDiscovered=Test-PodCIDR($podCIDR)
        }
    
        # stop the kubelet process now that we have our CIDR, discard the process output
        $process | Stop-Process | Out-Null
    }
    
    # startup the service
    
    $hnsNetwork = Get-HnsNetwork | ? Name -EQ $NetworkMode.ToLower()
    
    if (!$hnsNetwork) 
    {
        ipmo C:\k\hns.psm1
        $podGW = Get-PodGateway $podCIDR

        $hnsNetwork = New-HNSNetwork -Type $NetworkMode -AddressPrefix $podCIDR -Gateway $podGW -Name $NetworkMode.ToLower() -Verbose
        $podEndpointGW = Get-PodEndpointGateway $podCIDR

        $hnsEndpoint = New-HnsEndpoint -NetworkId $hnsNetwork.Id -Name $endpointName -IPAddress $podEndpointGW -Gateway "0.0.0.0" -Verbose
        Attach-HnsHostEndpoint -EndpointID $hnsEndpoint.Id -CompartmentID 1
        netsh int ipv4 set int "$vnicName" for=en
        #netsh int ipv4 set add "vEthernet (cbr0)" static $podGW 255.255.255.0
    }

    Start-Sleep 10
    # Add route to all other POD networks
    Update-CNIConfig $podCIDR

    c:\k\kubelet.exe --hostname-override=$(hostname) --pod-infra-container-image=kubletwin/pause --resolv-conf="" --allow-privileged=true --enable-debugging-handlers --cluster-dns=$KubeDnsServiceIp --cluster-domain=cluster.local  --kubeconfig=c:\k\config --hairpin-mode=promiscuous-bridge --v=6 --image-pull-progress-deadline=20m --cgroups-per-qos=false --enforce-node-allocatable="" --network-plugin=cni --cni-bin-dir=$CNIPath --cni-conf-dir $CNIPath\config
}
catch
{
    Write-Error $_
    Write-Error $Error
}
