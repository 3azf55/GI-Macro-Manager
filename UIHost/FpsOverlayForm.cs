using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;

namespace UMM.UI;

internal sealed class FpsOverlayForm : Form
{
    private const int WsExToolWindow = 0x00000080;
    private const int WsExNoActivate = 0x08000000;
    private const uint SwpNoActivate = 0x0010;
    private const uint SwpShowWindow = 0x0040;
    private static readonly nint HwndTopMost = new(-1);

    private readonly Font _captionFont = new("Segoe UI", 6.25f, FontStyle.Bold, GraphicsUnit.Point);
    private readonly Font _valueFont = new("Segoe UI", 10.25f, FontStyle.Bold, GraphicsUnit.Point);
    private int _framesPerSecond;
    private bool _lightTheme;
    private bool _dragging;
    private bool _positionInitialized;
    private nint _trackedGameWindow;
    private Point _dragStartCursor;
    private Point _dragStartLocation;
    private int _offsetX;
    private int _offsetY;

    public FpsOverlayForm()
    {
        AutoScaleMode = AutoScaleMode.Dpi;
        BackColor = Color.FromArgb(15, 18, 27);
        ClientSize = new Size(76, 26);
        ControlBox = false;
        Cursor = Cursors.SizeAll;
        FormBorderStyle = FormBorderStyle.None;
        MaximizeBox = false;
        MinimizeBox = false;
        Opacity = 0.72;
        ShowIcon = false;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        TopMost = true;
        DoubleBuffered = true;
        UpdateRoundedRegion();

        // Create the native handle on the UI thread so background monitoring
        // can safely marshal overlay updates with BeginInvoke().
        _ = Handle;
    }

    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            var parameters = base.CreateParams;
            parameters.ExStyle |= WsExToolWindow | WsExNoActivate;
            return parameters;
        }
    }

    public void Present(nint gameWindow, int gameProcessId, int framesPerSecond)
    {
        if (InvokeRequired)
        {
            BeginInvoke((Action)(() => Present(gameWindow, gameProcessId, framesPerSecond)));
            return;
        }

        if (IsDisposed || gameWindow == 0 || gameProcessId <= 0 ||
            !IsWindowVisible(gameWindow) || IsIconic(gameWindow) ||
            !IsGameForeground(gameProcessId) ||
            !GetClientRect(gameWindow, out var clientRectangle))
        {
            HideOverlay();
            return;
        }

        var clientOrigin = new NativePoint();
        if (!ClientToScreen(gameWindow, ref clientOrigin))
        {
            HideOverlay();
            return;
        }

        var scale = Math.Max(1f, DeviceDpi / 96f);
        var width = Math.Max(72, (int)Math.Round(76 * scale));
        var height = Math.Max(24, (int)Math.Round(26 * scale));
        var inset = Math.Max(6, (int)Math.Round(8 * scale));
        var clientWidth = clientRectangle.Right - clientRectangle.Left;
        var clientHeight = clientRectangle.Bottom - clientRectangle.Top;
        if (clientWidth < width + inset * 2 || clientHeight < height + inset * 2)
        {
            HideOverlay();
            return;
        }

        _framesPerSecond = Math.Clamp(framesPerSecond, 0, 9999);

        if (!_positionInitialized || _trackedGameWindow != gameWindow)
        {
            _trackedGameWindow = gameWindow;
            _offsetX = inset;
            _offsetY = inset;
            _positionInitialized = true;
        }

        if (_dragging)
        {
            StoreRelativePosition(clientOrigin, clientWidth, clientHeight, width, height);
        }

        _offsetX = Math.Clamp(_offsetX, 0, Math.Max(0, clientWidth - width));
        _offsetY = Math.Clamp(_offsetY, 0, Math.Max(0, clientHeight - height));
        var bounds = new Rectangle(
            clientOrigin.X + _offsetX,
            clientOrigin.Y + _offsetY,
            width,
            height);

        if (_dragging)
        {
            if (Size != bounds.Size)
            {
                Size = bounds.Size;
            }
        }
        else if (Bounds.Size != bounds.Size)
        {
            Bounds = bounds;
            UpdateRoundedRegion();
        }
        else
        {
            Location = bounds.Location;
        }

        Invalidate();
        if (!Visible)
        {
            Show();
        }

        SetWindowPos(
            Handle,
            HwndTopMost,
            Left,
            Top,
            Width,
            Height,
            SwpNoActivate | SwpShowWindow);
    }

    public void HideOverlay()
    {
        if (InvokeRequired)
        {
            BeginInvoke((Action)HideOverlay);
            return;
        }

        if (!IsDisposed && Visible)
        {
            Hide();
        }
    }

    public void SetTheme(string theme)
    {
        if (InvokeRequired)
        {
            BeginInvoke((Action)(() => SetTheme(theme)));
            return;
        }

        if (IsDisposed)
        {
            return;
        }

        _lightTheme = string.Equals(theme, "light", StringComparison.Ordinal);
        BackColor = _lightTheme
            ? Color.FromArgb(239, 243, 249)
            : Color.FromArgb(15, 18, 27);
        Invalidate();
    }

    protected override void OnPaint(PaintEventArgs eventArgs)
    {
        base.OnPaint(eventArgs);
        eventArgs.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        eventArgs.Graphics.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;

        var panelColor = _lightTheme
            ? Color.FromArgb(247, 249, 252)
            : Color.FromArgb(24, 29, 42);
        var borderColor = _lightTheme
            ? Color.FromArgb(105, 52, 88, 199)
            : Color.FromArgb(92, 142, 168, 255);
        var captionColor = _lightTheme
            ? Color.FromArgb(91, 105, 126)
            : Color.FromArgb(174, 184, 204);
        var valueColor = _lightTheme
            ? Color.FromArgb(52, 88, 199)
            : Color.FromArgb(180, 198, 255);

        using var panelBrush = new SolidBrush(panelColor);
        using var borderPen = new Pen(borderColor, Math.Max(1f, DeviceDpi / 96f));
        using var path = CreateRoundedPath(
            new RectangleF(1, 1, ClientSize.Width - 2, ClientSize.Height - 2),
            Math.Max(8f, 10f * DeviceDpi / 96f));
        eventArgs.Graphics.FillPath(panelBrush, path);
        eventArgs.Graphics.DrawPath(borderPen, path);

        var scale = Math.Max(1f, DeviceDpi / 96f);
        var captionRectangle = new Rectangle(
            (int)Math.Round(7 * scale),
            0,
            (int)Math.Round(22 * scale),
            ClientSize.Height);
        var valueRectangle = new Rectangle(
            (int)Math.Round(28 * scale),
            0,
            Math.Max(1, ClientSize.Width - (int)Math.Round(34 * scale)),
            ClientSize.Height);

        TextRenderer.DrawText(
            eventArgs.Graphics,
            "FPS",
            _captionFont,
            captionRectangle,
            captionColor,
            TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
        TextRenderer.DrawText(
            eventArgs.Graphics,
            _framesPerSecond.ToString(),
            _valueFont,
            valueRectangle,
            valueColor,
            TextFormatFlags.Right | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
    }

    protected override void OnMouseDown(MouseEventArgs eventArgs)
    {
        base.OnMouseDown(eventArgs);
        if (eventArgs.Button != MouseButtons.Left)
        {
            return;
        }

        _dragging = true;
        _dragStartCursor = System.Windows.Forms.Cursor.Position;
        _dragStartLocation = Location;
        Capture = true;
    }

    protected override void OnMouseMove(MouseEventArgs eventArgs)
    {
        base.OnMouseMove(eventArgs);
        if (!_dragging || (Control.MouseButtons & MouseButtons.Left) == 0)
        {
            return;
        }

        var cursor = System.Windows.Forms.Cursor.Position;
        Location = new Point(
            _dragStartLocation.X + cursor.X - _dragStartCursor.X,
            _dragStartLocation.Y + cursor.Y - _dragStartCursor.Y);
        StoreRelativePosition();
    }

    protected override void OnMouseUp(MouseEventArgs eventArgs)
    {
        base.OnMouseUp(eventArgs);
        if (eventArgs.Button == MouseButtons.Left)
        {
            EndDrag();
        }
    }

    protected override void OnMouseCaptureChanged(EventArgs eventArgs)
    {
        base.OnMouseCaptureChanged(eventArgs);
        if (_dragging && !Capture)
        {
            _dragging = false;
            StoreRelativePosition();
        }
    }

    protected override void OnSizeChanged(EventArgs eventArgs)
    {
        base.OnSizeChanged(eventArgs);
        UpdateRoundedRegion();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _captionFont.Dispose();
            _valueFont.Dispose();
            var roundedRegion = Region;
            Region = null;
            roundedRegion?.Dispose();
        }
        base.Dispose(disposing);
    }

    private void UpdateRoundedRegion()
    {
        if (ClientSize.Width <= 0 || ClientSize.Height <= 0)
        {
            return;
        }

        using var path = CreateRoundedPath(
            new RectangleF(0, 0, ClientSize.Width, ClientSize.Height),
            Math.Max(8f, 11f * DeviceDpi / 96f));
        var previousRegion = Region;
        Region = new Region(path);
        previousRegion?.Dispose();
    }

    private void EndDrag()
    {
        if (!_dragging)
        {
            return;
        }

        StoreRelativePosition();
        _dragging = false;
        Capture = false;
    }

    private void StoreRelativePosition()
    {
        if (_trackedGameWindow == 0 ||
            !GetClientRect(_trackedGameWindow, out var clientRectangle))
        {
            return;
        }

        var clientOrigin = new NativePoint();
        if (!ClientToScreen(_trackedGameWindow, ref clientOrigin))
        {
            return;
        }

        StoreRelativePosition(
            clientOrigin,
            clientRectangle.Right - clientRectangle.Left,
            clientRectangle.Bottom - clientRectangle.Top,
            Width,
            Height);
        Location = new Point(clientOrigin.X + _offsetX, clientOrigin.Y + _offsetY);
    }

    private void StoreRelativePosition(
        NativePoint clientOrigin,
        int clientWidth,
        int clientHeight,
        int overlayWidth,
        int overlayHeight)
    {
        _offsetX = Math.Clamp(Left - clientOrigin.X, 0, Math.Max(0, clientWidth - overlayWidth));
        _offsetY = Math.Clamp(Top - clientOrigin.Y, 0, Math.Max(0, clientHeight - overlayHeight));
        _positionInitialized = true;
    }

    private static GraphicsPath CreateRoundedPath(RectangleF rectangle, float radius)
    {
        var diameter = radius * 2;
        var path = new GraphicsPath();
        path.AddArc(rectangle.Left, rectangle.Top, diameter, diameter, 180, 90);
        path.AddArc(rectangle.Right - diameter, rectangle.Top, diameter, diameter, 270, 90);
        path.AddArc(rectangle.Right - diameter, rectangle.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(rectangle.Left, rectangle.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }

    private static bool IsGameForeground(int gameProcessId)
    {
        var foregroundWindow = GetForegroundWindow();
        if (foregroundWindow == 0)
        {
            return false;
        }

        GetWindowThreadProcessId(foregroundWindow, out var foregroundProcessId);
        return foregroundProcessId == (uint)gameProcessId;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRectangle
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    private static extern nint GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(nint window, out uint processId);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetClientRect(nint window, out NativeRectangle rectangle);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ClientToScreen(nint window, ref NativePoint point);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowVisible(nint window);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsIconic(nint window);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(
        nint window,
        nint insertAfter,
        int x,
        int y,
        int width,
        int height,
        uint flags);
}
