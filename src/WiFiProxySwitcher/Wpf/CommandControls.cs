using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Automation.Provider;
using System.Windows.Controls;
using System.Windows.Threading;

namespace WiFiProxySwitcher;

// Standard WPF selection/toggle providers change only IsChecked. These command
// controls expose the complete click operation to assistive technology and UIA.
// Mouse, keyboard and automation all execute the same ButtonBase.OnClick path.
public class CommandRadioButton : RadioButton
{
    protected override AutomationPeer OnCreateAutomationPeer() => new CommandRadioButtonPeer(this);
    internal void InvokeClick() => OnClick();
}

internal sealed class CommandRadioButtonPeer(CommandRadioButton owner) : RadioButtonAutomationPeer(owner), IInvokeProvider, ISelectionItemProvider
{
    public override object? GetPattern(PatternInterface patternInterface) => patternInterface == PatternInterface.Invoke ? this : base.GetPattern(patternInterface);
    public void Invoke()
    {
        if (!IsEnabled()) throw new ElementNotEnabledException();
        owner.Dispatcher.BeginInvoke(DispatcherPriority.Input, (Action)owner.InvokeClick);
    }
    void ISelectionItemProvider.Select() => Invoke();
    void ISelectionItemProvider.AddToSelection() => Invoke();
    void ISelectionItemProvider.RemoveFromSelection() => throw new InvalidOperationException("A radio button cannot remove its selection.");
    bool ISelectionItemProvider.IsSelected => owner.IsChecked == true;
    IRawElementProviderSimple ISelectionItemProvider.SelectionContainer => null!;
}

public class CommandCheckBox : CheckBox
{
    protected override AutomationPeer OnCreateAutomationPeer() => new CommandCheckBoxPeer(this);
    internal void InvokeClick() => OnClick();
}

internal sealed class CommandCheckBoxPeer(CommandCheckBox owner) : CheckBoxAutomationPeer(owner), IInvokeProvider, IToggleProvider
{
    public override object? GetPattern(PatternInterface patternInterface) => patternInterface is PatternInterface.Invoke or PatternInterface.Toggle ? this : base.GetPattern(patternInterface);
    public void Invoke()
    {
        if (!IsEnabled()) throw new ElementNotEnabledException();
        owner.Dispatcher.BeginInvoke(DispatcherPriority.Input, (Action)owner.InvokeClick);
    }
    void IToggleProvider.Toggle() => Invoke();
    ToggleState IToggleProvider.ToggleState => owner.IsChecked switch { true => ToggleState.On, false => ToggleState.Off, _ => ToggleState.Indeterminate };
}
