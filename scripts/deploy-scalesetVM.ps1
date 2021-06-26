Param(
    [string]$VMUserName ,
    [string]$VMUserPassword,
    [string]$VMName,
    [string]$ManagedImageResourceGroupName,
    [string]$ManagedImageName,
    [string]$AgentPoolResourceGroup,
    [string]$ScaleSetName,
    [string]$Location,
    [string]$SubscriptionId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Get-AzureRmResourceGroup -Name $AgentPoolResourceGroup -ev notPresent -ea 0

if (-Not $notPresent) {
    Write-Output "Removing $AgentPoolResourceGroup"
    Remove-AzureRmResourceGroup -Name $AgentPoolResourceGroup -Force 
}

Write-Output "Create a new resource group $AgentPoolResourceGroup"
New-AzureRmResourceGroup -Name $AgentPoolResourceGroup -Location $Location

Write-Output "Create a virtual network subnet"
$subnet = New-AzureRmVirtualNetworkSubnetConfig `
    -Name "Subnet" `
    -AddressPrefix 10.0.0.0/24

Write-Output "Create a virtual network"
$vnet = New-AzureRmVirtualNetwork `
    -ResourceGroupName $AgentPoolResourceGroup `
    -Name "AgentVnet" `
    -Location $Location `
    -AddressPrefix 10.0.0.0/16 `
    -Subnet $subnet `
    -Force

Write-Output "Create IP address configurations"
$ipConfig = New-AzureRmVmssIpConfig `
    -Name "IPConfig" `
    -SubnetId $vnet.Subnets[0].Id

Write-Output "Create a vmss config"
$vmssConfig = New-AzureRmVmssConfig `
    -Location $Location `
    -SkuCapacity 3 `
    -SkuName "Standard_DS2" `
    -UpgradePolicyMode Manual 

Write-Output "Set the VM image"
$image = Get-AzureRMImage -ImageName $ManagedImageName -ResourceGroupName $ManagedImageResourceGroupName
Set-AzureRmVmssStorageProfile $vmssConfig `
    -OsDiskCreateOption FromImage `
    -ManagedDisk Standard_LRS `
    -OsDiskCaching "None" `
    -OsDiskOsType Windows `
    -ImageReferenceId $image.id



Write-Output "Set up information for authenticating with the virtual machine"
Set-AzureRmVmssOsProfile $vmssConfig `
    -AdminUsername $VMUserName `
    -AdminPassword $VMUserPassword `
    -ComputerNamePrefix $VMName

Write-Output "Attach the virtual network to the config object"
Add-AzureRmVmssNetworkInterfaceConfiguration `
    -VirtualMachineScaleSet $vmssConfig `
    -Name "network-config" `
    -Primary $true `
    -IPConfiguration $ipConfig



Write-Output "Create the scale set with the config object (this step might take a few minutes)"
New-AzureRmVmss `
    -ResourceGroupName $AgentPoolResourceGroup `
    -Name $ScaleSetName `
    -VirtualMachineScaleSet $vmssConfig

    Write-output  "Attach Auto Scale config object"
    $myRuleScaleOut = New-AzureRmAutoscaleRule `
    -MetricName "Percentage CPU" `
    -MetricResourceId /subscriptions/$SubscriptionId/resourceGroups/$AgentPoolResourceGroup/providers/Microsoft.Compute/virtualMachineScaleSets/$ScaleSetName `
    -TimeGrain 00:01:00 `
    -MetricStatistic "Average" `
    -TimeWindow 00:05:00 `
    -Operator "GreaterThan" `
    -Threshold 70 `
    -ScaleActionDirection "Increase" `
    -ScaleActionScaleType "ChangeCount" `
    -ScaleActionValue 3 `
    -ScaleActionCooldown 00:05:00
  
      $myRuleScaleIn = New-AzureRmAutoscaleRule `
      -MetricName "Percentage CPU" `
      -MetricResourceId /subscriptions/$SubscriptionId/resourceGroups/$AgentPoolResourceGroup/providers/Microsoft.Compute/virtualMachineScaleSets/$ScaleSetName `
      -Operator "LessThan" `
      -MetricStatistic "Average" `
      -Threshold 30 `
      -TimeGrain 00:01:00 `
      -TimeWindow 00:05:00 `
      -ScaleActionCooldown 00:05:00 `
      -ScaleActionDirection "Decrease" `
      -ScaleActionScaleType "ChangeCount" `
      -ScaleActionValue 1
  
      $myScaleProfile = New-AzureRmAutoscaleProfile `
    -DefaultCapacity 2  `
    -MaximumCapacity 10 `
    -MinimumCapacity 2 `
    -Rule $myRuleScaleOut,$myRuleScaleIn `
    -Name "autoaviprofile"
  
    Add-AzureRmAutoscaleSetting `
    -Location $Location `
    -Name "autosetting" `
    -ResourceGroup $AgentPoolResourceGroup `
    -TargetResourceId /subscriptions/$SubscriptionId/resourceGroups/$AgentPoolResourceGroup/providers/Microsoft.Compute/virtualMachineScaleSets/$ScaleSetName `
    -AutoscaleProfile $myScaleProfile
