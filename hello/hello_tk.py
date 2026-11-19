import tkinter as tk
from tkinter import messagebox
import sys


def on_click():
    # Get the current Python version
    py_version = sys.version.split()[0]

    # Pop up an information dialog box
    messagebox.showinfo(
        title="Test Successful",
        message=f"Congratulations! Tkinter is running perfectly!\nCurrent Python Version: {py_version}",
    )


def main():
    # Create the main application window
    root = tk.Tk()
    root.title("Portable GUI Test")

    # Define window dimensions and calculate center position
    window_width = 350
    window_height = 200
    screen_width = root.winfo_screenwidth()
    screen_height = root.winfo_screenheight()

    center_x = int(screen_width / 2 - window_width / 2)
    center_y = int(screen_height / 2 - window_height / 2)

    # Apply geometry (size and position)
    root.geometry(f"{window_width}x{window_height}+{center_x}+{center_y}")

    # Add a welcome label
    label = tk.Label(root, text="Hello, Portable Tkinter!", font=("Arial", 14, "bold"))
    label.pack(pady=30)

    # Add an interactive button
    btn = tk.Button(root, text="Click to Test", font=("Arial", 12), command=on_click)
    btn.pack()

    # Start the main GUI event loop
    root.mainloop()


if __name__ == "__main__":
    main()
