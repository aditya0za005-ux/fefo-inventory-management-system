const base = import.meta.env.VITE_API_URL || '/api/v1';

let onUnauthorized: () => void = () => {};

export const setUnauthorizedHandler = (handler: () => void) => {
    onUnauthorized = handler;
};

export async function api<T>(path: string, options: RequestInit = {}): Promise<T> {
    const token = localStorage.getItem('accessToken');
    const headers = new Headers(options.headers);

    if (!headers.has('Content-Type') && options.body) {
        headers.set('Content-Type', 'application/json');
    }

    if (token) {
        headers.set('Authorization', `Bearer ${token}`);
    }

    const response = await fetch(`${base}${path}`, {
        ...options,
        headers
    });

    if (response.status === 401) {
        localStorage.removeItem('accessToken');
        localStorage.removeItem('role');
        onUnauthorized();
        throw new Error('Unauthorized. Please sign in again.');
    }

    if (!response.ok) {
        let detail = `Request failed (${response.status})`;

        try {
            const problem = await response.json();
            detail = problem.detail || detail;
        } catch {
            // Keep the HTTP status message when the server did not return JSON.
        }

        throw new Error(detail);
    }

    if (response.status === 204) {
        return undefined as T;
    }

    return response.json() as Promise<T>;
}

export const authApi = {
    login: (username: string, password: string) =>
        api<import('../types').LoginResponse>('/auth/login', {
            method: 'POST',
            body: JSON.stringify({ username, password })
        })
};
