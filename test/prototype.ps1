set-strictmode -version 2

function New-ScriptClass2 {
    param(
        $Name,
        $ClassDefinitionBlock
    )

    $classDefinition = GetClassDefinition $classDefinitionBlock

    $properties = GetProperties $classDefinition.Module InstanceProperty
    $staticProperties = GetProperties $classDefinition.StaticModule StaticProperty

    $methods = GetMethods $classDefinition.Module $Name InstanceMethod
    $methods += GetMethods $classDefinition.StaticModule $Name StaticMethod

    $classBlock = GetClassBlock $Name $classDefinition.Module $properties $methods $staticProperties

    $newClass = $classDefinition.classObject.InvokeScript($classBlock, $classDefinition.Module, $classDefinition.StaticModule, $properties, $staticProperties)

    AddClassType $Name $newClass $classDefinition
}

enum MethodType {
    Constructor
    StaticConstructor
    InstanceMethod
    StaticMethod
}

enum PropertyType {
    InstanceProperty
    StaticProperty
}

function GetClassDefinition($classDefinitionBlock) {
    $classModuleInfo = @{}

    $classObject = new-module -ascustomobject $classModuleBlock -argumentlist $classDefinitionBlock, $classModuleInfo

    [PSCustomObject] @{
        ClassObject = $classObject
        Module = $classModuleInfo.Module
        StaticModule = $classModuleInfo.StaticModule
    }
}

function GetClassBlock($className, $classModuleName, $properties, $methods, $staticProperties) {
    $propertyDeclaration = ( GetPropertyDefinitions $properties ) -join "`n"
    $propertyDeclaration += "`n" + ( GetPropertyDefinitions $staticProperties ) -join "`n"

    $methodDeclaration = ( GetMethodDefinitions $methods $className ) -join "`n"

    $classInstanceId = $classModuleName -replace '-', '_'

    $classFragment = $classTemplate -f $className, $propertyDeclaration, $methodDeclaration, $classInstanceId

    $global:myfrag = $classFragment
    [ScriptBlock]::Create($classFragment)
}

function NewMethod($methodName, $scriptBlock, [MethodType] $methodType) {
    [PSCustomObject] @{
        Name = $methodName
        ScriptBlock = $scriptblock
        MethodType = $methodType
    }
}

function NewProperty($propertyName, $type, $value, [PropertyType] $propertyType = 'InstanceProperty' ) {
    [PSCustomObject] @{
        Name = $propertyName
        Type = $type
        Value = $value
        PropertyType = $propertyType
    }
}

function GetMethods($classModule, $className, $methodType) {
    $methods = @{}

    foreach ( $functionName in $classModule.ExportedFunctions.Keys ) {
        if ( $functionName -in $internalFunctions ) {
            continue
        }

        $method = NewMethod $functionName $classModule.ExportedFunctions[$functionName].scriptblock $methodType

        $methods.Add($method.Name, $method)
    }

    $constructor = $methods[(GetConstructorMethodName $className)]

    if ( $constructor ) {
       $constructor.MethodType = [MethodType]::Constructor
    }

    $methods
}

function GetConstructorMethodName($className) {
    '__initialize'
}

function GetProperties($classmodule, [PropertyType] $propertyType) {
    $properties = @{}

    foreach ( $propertyName in $classModule.ExportedVariables.Keys ) {
        if ( $propertyName -in $internalProperties ) {
            continue
        }

        $propertyValue = $classModule.ExportedVariables[$propertyName]
        $type = if ( $propertyValue -ne $null -and $propertyValue.value -ne $null ) {
            $propertyValue.value.GetType()
        }

        $property = NewProperty $propertyName $type $propertyValue $propertyType
        $properties.Add($propertyName, $property)
    }

    $properties
}

function GetMethodParameters($scriptBlock) {
    $scriptBlock.ast.Parameters
}

function GetMethodParameterList($parameters) {
    if ( $parameters ) {
        ( $parameters | foreach { $_.name.tostring() } ) -join ','
    } else {
        @()
    }
}

function NewClassInfo($className, $class, $classObject, $classModule, $staticModule) {
    if ( $classObject -eq $null ) {
        throw 'anger3'
    }

    [PSCustomObject] @{
        Name = $className
        Class = $class
        ClassObject = $classObject
        Module = $classModule
        StaticModule = $staticModule
    }
}

function NewMethodDefinition($methodName, $scriptblock, $isStatic, $staticMethodClassName) {
    $parameters = if ( $scriptblock.ast.body.paramblock ) {
        $scriptblock.ast.body.paramblock.parameters
    } else {
        $scriptblock.ast.parameters
    }

    $parameterList = GetMethodParameterList $parameters

    if ( $isStatic ) {
        $staticMethodTemplate -f $methodname, $parameterList, $parameterList, $staticMethodClassName
    } else {
        $methodTemplate -f $methodname, $parameterList, $parameterList
    }
}

function GetMethodDefinitions($methods, $className) {
    foreach ( $method in $methods.values ) {
        NewMethodDefinition $method.Name $method.scriptblock ($method.methodType -eq 'StaticMethod') $className
    }
}

function NewPropertyDefinition($propertyName, $type, $value, [PropertyType] $propertyType) {
    $staticElement = if ( $propertyType -eq [PropertyType]::StaticProperty ) {
        'static'
    } else {
        ''
    }

    $typeElement = if ( $type ) {
        "[$type]"
    } else {
        ''
    }

    $propertyTemplate -f $propertyName, $typeElement, $staticElement
}

function GetPropertyDefinitions($properties) {
    $global:myprops = $properties
    foreach ( $property in $properties.values ) {
        NewPropertyDefinition $property.name $property.type $property.value $property.propertyType
    }
}

function AddClassType($className, $classType, $classDefinition) {
    $classTable[$className] = NewClassInfo $className $classType $classDefinition.classObject $classDefinition.Module $classDefinition.StaticModule
}

function Get-ScriptClass2 {
    [cmdletbinding()]
    param($className)

    $class = $classTable[$className]

    if ( ! $class ) {
        throw [ArgumentException]::new("The specified class '$ClassName' could not be found.")
    }

    $class
}

function New-ScriptObject2 {
    [cmdletbinding()]
    param($ClassName)

    $classInfo = Get-ScriptClass2 $ClassName

    $nativeObject = $classInfo.class::new($classInfo.module, $args)

    [PSObject]::new($nativeObject)
}

# Even though there is no cmdletbinding, this works with -verbose!
function ==> {
    param(
        [string] $methodName
    )

    foreach ( $object in $input ) {
        $object.InvokeMethod($methodName, $args)
    }
}

$classModuleBlock = {
    param($__classDefinitionBlock, $__moduleInfo)

    set-strictmode -version 2

    $__moduleInfo['Statics'] = @()

    $__moduleInfo['Module'] = {}.module
    new-module {param([HashTable] $moduleInfo) $moduleInfo['StaticModule'] = {}.module } -ascustomobject -argumentlist $__moduleInfo | out-null

    function __initialize {}

    function static([ScriptBlock] $staticDefinition) {
        set-strictmode -version 2

        $readerBlock = {
            param($__inputBlock)
            set-strictmode -version 2

            . {}.module.newboundscriptblock($__inputBlock)
            get-variable __inputBlock | remove-variable
            export-modulemember -variable * -function *
        }

        $staticObject = new-module -ascustomobject $readerBlock -argumentlist $staticDefinition

        $methods = $staticObject | gm -MemberType ScriptMethod
        $properties = $staticObject | gm -MemberType NoteProperty
        $staticModule = $__moduleInfo['StaticModule']

        $methodSetTranslatorBlock = {
            param($methods, $properties, $staticObject)
            set-strictmode -version 2

            $methodTranslatorBlock = {param($methodName, $methodScript) remove-item function:$methodName -erroraction ignore; new-item function:$methodName -value {}.module.newboundscriptblock($methodScript)}
            $methodNames = @()
            foreach ( $method in $methods ) {
                $methodScript = $staticObject.psobject.methods | where name -eq $method.name | select -expandproperty script
                . $methodTranslatorBlock $method.name $methodScript | out-null
                $methodNames += $method.name
            }

            $propertyNames = @()
            $propertyTranslatorBlock = {param($propertyName, $propertyValue) new-variable $propertyName -value $propertyValue }
            foreach ( $property in $properties ) {
                . $propertyTranslatorBlock $property.name $staticObject.$($property.name) | out-null
                $propertyNames += $property.name
            }

            export-modulemember -variable $propertyNames -function $methodNames
        }

        . $staticModule.newboundscriptblock($methodSetTranslatorBlock) $methods $properties $staticObject

        $__moduleInfo['Statics'] += [PSCustomObject] @{StaticMethods=$methods;StaticProperties=$Properties}
    }

    . {}.Module.NewBoundScriptBlock($__classDefinitionBlock)

    function InvokeScript([ScriptBlock] $scriptBlock) {
        . {}.module.NewBoundScriptBlock($scriptBlock) @args
    }

    function InvokeMethod($methodName, [object[]] $methodArgs) {
        if ( ! ( $this | gm -membertype method $methodName -erroraction ignore ) ) {
            throw "The method '$methodName' is not defined for this object of type $($this.gettype().fullname)"
        }

        & $methodName @methodArgs
    }

    get-variable __classDefinitionBlock, __moduleInfo | remove-variable

    export-modulemember -variable * -function *
}

$internalFunctions = '__initialize', 'static'
$internalProperties = '__module', '__classDefinitionBlock'

$propertyTemplate = @'
    {2} {1} ${0} = $null
'@

$methodTemplate = @'
    [object] {0}({1}) {{
        $thisVariable = [PSVariable]::new('this', $this)
        $methodBlock = (get-item function:{0}).scriptblock
        $__result = $methodBlock.InvokeWithContext(@{{}}, $thisVariable, @({2}))
        return $__result
    }}
'@

$staticMethodTemplate = @'
    static [object] {0}({1}) {{
        $thisVariable = [PSVariable]::new('this', [{3}])
        $methodBlock = [{3}]::StaticModule.Invoke({{(get-item function:{0}).scriptblock}})
        $__result = $methodBlock.InvokeWithContext(@{{}}, $thisVariable, @({2}))
        return $__result
    }}
'@

$classTemplate = @'
param($module, $staticModule, $properties, $staticProperties)

Class BaseModule__{3} {{
    static $Properties = $null
    static $StaticProperties = $null
    static $Module = $null
    static $StaticModule = $null
}}

[BaseModule__{3}]::Properties = $properties.values | where PropertyType -eq 'InstanceProperty'
[BaseModule__{3}]::StaticProperties = $staticProperties.values | where PropertyType -eq 'StaticProperty'
[BaseModule__{3}]::Module = $module
[BaseModule__{3}]::StaticModule = $staticModule

class {0} : BaseModule__{3} {{

    static {0}() {{
        [BaseModule__{3}]::Module | import-module
        foreach ( $property in [BaseModule__{3}]::StaticProperties ) {{
            [{0}]::$($property.name) = $property.value.value
        }}
    }}

    {0}($classModule, [object[]] $constructorArgs) {{
       foreach ( $property in [BaseModule__{3}]::Properties ) {{
           $this.$($property.name) = $property.value.value
       }}
        __initialize @constructorArgs
    }}

    {1}

    {2}
}}

[{0}]
'@


$classTable = @{}

set-alias scriptclass2 New-ScriptClass2
set-alias new-so2 New-ScriptObject2

<#
# Wow, this works!
new-scriptclass2 Fun1 {$stuff = 2; function multme($arg1, $arg2) { $arg1 * $argnew-scriptclass2 Fun1 {$stuff = 2; function multme($arg1, $arg2) { $arg1 * $argnew-scriptclass2 Fun1 {$stuff = 2; function multme($arg1, $arg2) { $arg1 * $arg2}; function saveme($myval) { $this.stuff = $myval}; function getme { $this.stuff}; function addtome($argn) {multme $this.stuff $argn};function MultSave($argadd) { $res = multme $this.stuff $argadd; saveme $res}}

$fun = New-ScriptObject2 fun1

#>

# This actually works pretty well too!
<#
new-scriptclass2 Thrower {
    $shouldthrow = $false

    function level1($throwme) {
        $this.shouldthrow = $throwme
        level2
    }

    function level2 {
        if ( $this.shouldthrow ) {
            throw 'me'
        }
    }
}
                                                                                                                                               #>

# Errors are something like that below -- error[0] looks useless,
# but $error[1] has everything -- no need to explore $error after this
<#
PS> $error[0].scriptstacktrace
at level1, <No file>: line 15
at <ScriptBlock>, <No file>: line 1
PS> $error[1].scriptstacktrace
at level2, C:\Users\adamedx\OneDrive\scripts\classmod3.ps1: line 286
at level1, C:\Users\adamedx\OneDrive\scripts\classmod3.ps1: line 281
at level1, <No file>: line 15
at <ScriptBlock>, <No file>: line 1
#>
